import Foundation
import Combine

public class Client {
    private static let authTypes = ["sa", "hsa", "non-sa", "hsa2"]

    public init() {}

    // MARK: - Login

    public func login(accountName: String, password: String) -> AnyPublisher<AuthenticationState, Swift.Error> {
        var serviceKey: String!

        return Current.network.dataTask(with: URLRequest.itcServiceKey)
            .map(\.data)
            .decode(type: ServiceKeyResponse.self, decoder: JSONDecoder())
            .flatMap { serviceKeyResponse -> AnyPublisher<URLSession.DataTaskPublisher.Output, Swift.Error> in
                serviceKey = serviceKeyResponse.authServiceKey
                return Current.network.dataTask(with: URLRequest.signIn(serviceKey: serviceKey, accountName: accountName, password: password))
                    .mapError { $0 as Swift.Error }
                    .eraseToAnyPublisher()
            }
            .flatMap { result -> AnyPublisher<AuthenticationState, Swift.Error> in
                let (data, response) = result
                return Just(data)
                    .decode(type: SignInResponse.self, decoder: JSONDecoder())
                    .flatMap { responseBody -> AnyPublisher<AuthenticationState, Swift.Error> in
                        let httpResponse = response as! HTTPURLResponse
                        
                        switch httpResponse.statusCode {
                        case 200:
                            return Current.network.dataTask(with: URLRequest.olympusSession)
                                .map { _ in AuthenticationState.authenticated }
                                .mapError { $0 as Swift.Error }
                                .eraseToAnyPublisher()
                        case 401:
                            return Fail(error: AuthenticationError.invalidUsernameOrPassword(username: accountName))
                                .eraseToAnyPublisher()
                        case 409:
                            return self.handleTwoStepOrFactor(data: data, response: response, serviceKey: serviceKey)
                        case 412 where Client.authTypes.contains(responseBody.authType ?? ""):
                            return Fail(error: AuthenticationError.appleIDAndPrivacyAcknowledgementRequired)
                                .eraseToAnyPublisher()
                        default:
                            return Fail(error: AuthenticationError.unexpectedSignInResponse(statusCode: httpResponse.statusCode,
                                                                 message: responseBody.serviceErrors?.map { $0.description }.joined(separator: ", ")))
                                .eraseToAnyPublisher()
                        }
                    }
                    .eraseToAnyPublisher()
            }
            .mapError { $0 as Swift.Error }
            .eraseToAnyPublisher()
    }

    func handleTwoStepOrFactor(data: Data, response: URLResponse, serviceKey: String) -> AnyPublisher<AuthenticationState, Swift.Error> {
        let httpResponse = response as! HTTPURLResponse
        let sessionID = (httpResponse.allHeaderFields["X-Apple-ID-Session-Id"] as! String)
        let scnt = (httpResponse.allHeaderFields["scnt"] as! String)

        return Current.network.dataTask(with: URLRequest.authOptions(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
            .map(\.data)
            .decode(type: AuthOptionsResponse.self, decoder: JSONDecoder())
            .flatMap { authOptions -> AnyPublisher<AuthenticationState, Error> in
                switch authOptions.kind {
                case .twoStep:
                    return Fail(error: AuthenticationError.accountUsesTwoStepAuthentication)
                        .eraseToAnyPublisher()
                case .twoFactor:
                    return self.handleTwoFactor(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, authOptions: authOptions)
                        .eraseToAnyPublisher()
                case .unknown:
                    let possibleResponseString = String(data: data, encoding: .utf8)
                    return Fail(error: AuthenticationError.accountUsesUnknownAuthenticationKind(possibleResponseString))
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    func handleTwoFactor(serviceKey: String, sessionID: String, scnt: String, authOptions: AuthOptionsResponse) -> AnyPublisher<AuthenticationState, Error> {
        let option: TwoFactorOption

        // SMS was sent automatically 
        if authOptions.smsAutomaticallySent {
            option = .smsSent(authOptions.trustedPhoneNumbers!.first!)
        // SMS wasn't sent automatically because user needs to choose a phone to send to
        } else if authOptions.canFallBackToSMS {
            option = .smsPendingChoice
        // Code is shown on trusted devices
        } else {
            option = .codeSent
        }
        
        let sessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        return Just(AuthenticationState.waitingForSecondFactor(option, authOptions, sessionData))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Continue 2FA
    
    public func requestSMSSecurityCode(to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber, authOptions: AuthOptionsResponse, sessionData: AppleSessionData) -> AnyPublisher<AuthenticationState, Error> {
        Result {
            try URLRequest.requestSecurityCode(serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt, trustedPhoneID: trustedPhoneNumber.id)
        }
        .publisher
        .flatMap { request in
            Current.network.dataTask(with: request)
                .mapError { $0 as Error } 
        }
        .map { _ in AuthenticationState.waitingForSecondFactor(.smsSent(trustedPhoneNumber), authOptions, sessionData) }
        .eraseToAnyPublisher()
    }
    
    public func submitSecurityCode(_ code: SecurityCode, sessionData: AppleSessionData) -> AnyPublisher<AuthenticationState, Error> {
        Result {
            try URLRequest.submitSecurityCode(serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt, code: code)
        }
        .publisher
        .flatMap { request in
            Current.network.dataTask(with: request)
                .mapError { $0 as Error }
                .tryMap { (data, response) throws -> (Data, URLResponse) in
                    guard let urlResponse = response as? HTTPURLResponse else { return (data, response) }
                    switch urlResponse.statusCode {
                    case 200..<300:
                        return (data, urlResponse)
                    case 401:
                        throw AuthenticationError.incorrectSecurityCode
                    case let code:
                        throw AuthenticationError.badStatusCode(code, data, urlResponse)
                    }
                }
                .flatMap { (data, response) -> AnyPublisher<AuthenticationState, Error> in
                    self.updateSession(serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
                }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Session
    
    /// Use the olympus session endpoint to see if the existing session is still valid
    public func validateSession() -> AnyPublisher<Void, Error> {
        return Current.network.dataTask(with: URLRequest.olympusSession)
            .tryMap { (data, response) in
                guard
                    let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    jsonObject["provider"] != nil
                else { throw AuthenticationError.invalidSession }
            }
            .eraseToAnyPublisher()
    }
    
    func updateSession(serviceKey: String, sessionID: String, scnt: String) -> AnyPublisher<AuthenticationState, Error> {
        return Current.network.dataTask(with: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
            .flatMap { (data, response) in
                Current.network.dataTask(with: URLRequest.olympusSession)
                    .map { _ in AuthenticationState.authenticated }
            }
            .mapError { $0 as Error }
            .eraseToAnyPublisher()
    }
}

// MARK: - Types

public enum AuthenticationState: Equatable {
    case unauthenticated
    case waitingForSecondFactor(TwoFactorOption, AuthOptionsResponse, AppleSessionData)
    case authenticated
}

public enum AuthenticationError: Swift.Error, LocalizedError, Equatable {
    case invalidSession
    case invalidUsernameOrPassword(username: String)
    case incorrectSecurityCode
    case unexpectedSignInResponse(statusCode: Int, message: String?)
    case appleIDAndPrivacyAcknowledgementRequired
    case accountUsesTwoStepAuthentication
    case accountUsesUnknownAuthenticationKind(String?)
    case badStatusCode(Int, Data, HTTPURLResponse)

    public var errorDescription: String? {
        switch self {
        case .invalidUsernameOrPassword(let username):
            return "Invalid username and password combination. Attempted to sign in with username \(username)."
        case .appleIDAndPrivacyAcknowledgementRequired:
            return "You must sign in to https://appstoreconnect.apple.com and acknowledge the Apple ID & Privacy agreement."
        case .accountUsesTwoStepAuthentication:
            return "Received a response from Apple that indicates this account has two-step authentication enabled. xcodes currently only supports the newer two-factor authentication, though. Please consider upgrading to two-factor authentication, or open an issue on GitHub explaining why this isn't an option for you here: https://github.com/RobotsAndPencils/xcodes/issues/new"
        case .accountUsesUnknownAuthenticationKind:
            return "Received a response from Apple that indicates this account has two-step or two-factor authentication enabled, but xcodes is unsure how to handle this response:"
        default:
            return String(describing: self)
        }
    }
}

public struct AppleSessionData: Equatable, Identifiable {    
    public let serviceKey: String
    public let sessionID: String 
    public let scnt: String
    
    public var id: String { sessionID }

    public init(serviceKey: String, sessionID: String, scnt: String) {
        self.serviceKey = serviceKey
        self.sessionID = sessionID
        self.scnt = scnt
    }
}

struct ServiceKeyResponse: Decodable {
    let authServiceKey: String
}

struct SignInResponse: Decodable {
    let authType: String?
    let serviceErrors: [ServiceError]?
    
    struct ServiceError: Decodable, CustomStringConvertible {
        let code: String
        let message: String
        
        var description: String {
            return "\(code): \(message)"
        }
    }
}

public enum TwoFactorOption: Equatable {
    case smsSent(AuthOptionsResponse.TrustedPhoneNumber)
    case codeSent
    case smsPendingChoice
}

public struct AuthOptionsResponse: Equatable, Decodable {
    public let trustedPhoneNumbers: [TrustedPhoneNumber]?
    public let trustedDevices: [TrustedDevice]?
    public let securityCode: SecurityCodeInfo
    public let noTrustedDevices: Bool?
    public let serviceErrors: [ServiceError]?
    
    public init(
        trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]?, 
        trustedDevices: [AuthOptionsResponse.TrustedDevice]?, 
        securityCode: AuthOptionsResponse.SecurityCodeInfo, 
        noTrustedDevices: Bool? = nil, 
        serviceErrors: [ServiceError]? = nil
    ) {
        self.trustedPhoneNumbers = trustedPhoneNumbers
        self.trustedDevices = trustedDevices
        self.securityCode = securityCode
        self.noTrustedDevices = noTrustedDevices
        self.serviceErrors = serviceErrors
    }
    
    public var kind: Kind {
        if trustedDevices != nil {
            return .twoStep
        } else if trustedPhoneNumbers != nil {
            return .twoFactor
        } else {
            return .unknown
        }
    }
    
    // One time with a new testing account I had a response where noTrustedDevices was nil, but the account didn't have any trusted devices.
    // This should have been a situation where an SMS security code was sent automatically.
    // This resolved itself either after some time passed, or by signing into appleid.apple.com with the account.
    // Not sure if it's worth explicitly handling this case or if it'll be really rare.
    public var canFallBackToSMS: Bool {
        noTrustedDevices == true
    }
    
    public var smsAutomaticallySent: Bool {
        trustedPhoneNumbers?.count == 1 && canFallBackToSMS
    }
    
    public struct TrustedPhoneNumber: Equatable, Decodable, Identifiable {
        public let id: Int
        public let numberWithDialCode: String

        public init(id: Int, numberWithDialCode: String) {
            self.id = id
            self.numberWithDialCode = numberWithDialCode
        }
    }
    
    public struct TrustedDevice: Equatable, Decodable {        
        public let id: String
        public let name: String
        public let modelName: String

        public init(id: String, name: String, modelName: String) {
            self.id = id
            self.name = name
            self.modelName = modelName
        }
    }
    
    public struct SecurityCodeInfo: Equatable, Decodable {        
        public let length: Int
        public let tooManyCodesSent: Bool
        public let tooManyCodesValidated: Bool
        public let securityCodeLocked: Bool
        public let securityCodeCooldown: Bool

        public init(
            length: Int,
            tooManyCodesSent: Bool = false,
            tooManyCodesValidated: Bool = false,
            securityCodeLocked: Bool = false,
            securityCodeCooldown: Bool = false
        ) {
            self.length = length
            self.tooManyCodesSent = tooManyCodesSent
            self.tooManyCodesValidated = tooManyCodesValidated
            self.securityCodeLocked = securityCodeLocked
            self.securityCodeCooldown = securityCodeCooldown
        }
    }
    
    public enum Kind: Equatable {
        case twoStep, twoFactor, unknown
    }
}

public struct ServiceError: Decodable, Equatable {
    let code: String
    let message: String
}

public enum SecurityCode {
    case device(code: String)
    case sms(code: String, phoneNumberId: Int)
    
    var urlPathComponent: String {
        switch self {
        case .device: return "trusteddevice"
        case .sms: return "phone"
        }
    }
}
