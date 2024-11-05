import Foundation
import Combine
import SRP
import Crypto
import CommonCrypto


public class Client {
    private static let authTypes = ["sa", "hsa", "non-sa", "hsa2"]

    public init() {}

    // MARK: - Login

    public func srpLogin(accountName: String, password: String) -> AnyPublisher<AuthenticationState, Swift.Error> {
        var serviceKey: String!
        
        let client = SRPClient(configuration: SRPConfiguration<SHA256>(.N2048))
        let clientKeys = client.generateKeys()
        let a = clientKeys.public

        return Current.network.dataTask(with: URLRequest.itcServiceKey)
            .map(\.data)
            .decode(type: ServiceKeyResponse.self, decoder: JSONDecoder())
            .flatMap { serviceKeyResponse -> AnyPublisher<(String, String), Swift.Error> in
                serviceKey = serviceKeyResponse.authServiceKey
                
                // Fixes issue https://github.com/RobotsAndPencils/XcodesApp/issues/360
                // On 2023-02-23, Apple added a custom implementation of hashcash to their auth flow
                // Without this addition, Apple ID's would get set to locked
                return self.loadHashcash(accountName: accountName, serviceKey: serviceKey)
                    .map { return (serviceKey, $0)}
                    .eraseToAnyPublisher()
            }
            .flatMap { (serviceKey, hashcash) -> AnyPublisher<(String, String, ServerSRPInitResponse), Swift.Error> in
                
                return Current.network.dataTask(with: URLRequest.SRPInit(serviceKey: serviceKey, a: Data(a.bytes).base64EncodedString(), accountName: accountName))
                    .map(\.data)
                    .decode(type: ServerSRPInitResponse.self, decoder: JSONDecoder())
                    .map { return (serviceKey, hashcash, $0) }
                    .eraseToAnyPublisher()
            }
            .flatMap { (serviceKey, hashcash, srpInit) -> AnyPublisher<URLSession.DataTaskPublisher.Output, Swift.Error> in
                guard let decodedB = Data(base64Encoded: srpInit.b) else {
                    return Fail(error: AuthenticationError.srpInvalidPublicKey)
                        .eraseToAnyPublisher()
                }
                
                guard let decodedSalt = Data(base64Encoded: srpInit.salt) else {
                    return Fail(error: AuthenticationError.srpInvalidPublicKey)
                        .eraseToAnyPublisher()
                }

                let iterations = srpInit.iteration
                
                do {
                    guard let encryptedPassword = self.pbkdf2(password: password, saltData: decodedSalt, keyByteCount: 32, prf: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds: iterations, protocol: srpInit.protocol) else {
                        return Fail(error: AuthenticationError.srpInvalidPublicKey)
                            .eraseToAnyPublisher()
                    }
                    
                    let sharedSecret = try client.calculateSharedSecret(password: encryptedPassword, salt: [UInt8](decodedSalt), clientKeys: clientKeys, serverPublicKey: .init([UInt8](decodedB)))
                    
                    let m1 = client.calculateClientProof(username: accountName, salt: [UInt8](decodedSalt), clientPublicKey: a, serverPublicKey: .init([UInt8](decodedB)), sharedSecret: .init(sharedSecret.bytes))
                    let m2 = client.calculateServerProof(clientPublicKey: a, clientProof: m1, sharedSecret: .init([UInt8](sharedSecret.bytes)))

                    return Current.network.dataTask(with: URLRequest.SRPComplete(serviceKey: serviceKey, hashcash: hashcash, accountName: accountName, c: srpInit.c, m1: Data(m1).base64EncodedString(), m2: Data(m2).base64EncodedString()))
                            .mapError { $0 as Swift.Error }
                            .eraseToAnyPublisher()
                } catch {
                    return Fail(error: AuthenticationError.srpInvalidPublicKey)
                        .eraseToAnyPublisher()
                }
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
                        case 403:
                            let errorMessage = responseBody.serviceErrors?.first?.description.replacingOccurrences(of: "-20209: ", with: "") ?? ""
                            return Fail(error: AuthenticationError.accountLocked(errorMessage))
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
    
    func loadHashcash(accountName: String, serviceKey: String) -> AnyPublisher<String, Swift.Error> {
        
        Result {
            try URLRequest.federate(account: accountName, serviceKey: serviceKey)
        }
        .publisher
        .flatMap { request in
            Current.network.dataTask(with: request)
                .mapError { $0 as Error }
                .tryMap { (data, response) throws -> (String) in
                    guard let urlResponse = response as? HTTPURLResponse else {
                        throw AuthenticationError.invalidSession
                    }
                    switch urlResponse.statusCode {
                    case 200..<300:
                        
                        let httpResponse = response as! HTTPURLResponse
                        guard let bitsString = httpResponse.allHeaderFields["X-Apple-HC-Bits"] as? String, let bits = UInt(bitsString) else {
                            throw AuthenticationError.invalidHashcash
                        }
                        guard let challenge = httpResponse.allHeaderFields["X-Apple-HC-Challenge"] as? String else {
                            throw AuthenticationError.invalidHashcash
                        }
                        guard let hashcash = Hashcash().mint(resource: challenge, bits: bits) else {
                            throw AuthenticationError.invalidHashcash
                        }
                        return (hashcash)
                    case 400, 401:
                        throw AuthenticationError.invalidHashcash
                    case let code:
                        throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
                    }
                }
        }
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
                case .twoFactor, .securityKey:
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
        } else if authOptions.fsaChallenge != nil {
            option = .securityKey
            // User needs to use a physical security key to respond to the challenge
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
                    case 400, 401:
                        throw AuthenticationError.incorrectSecurityCode
                    case 412:
                        throw AuthenticationError.appleIDAndPrivacyAcknowledgementRequired
                    case let code:
                        throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
                    }
                }
                .flatMap { (data, response) -> AnyPublisher<AuthenticationState, Error> in
                    self.updateSession(serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
                }
        }
        .eraseToAnyPublisher()
    }
    
    public func submitChallenge(response: Data, sessionData: AppleSessionData) -> AnyPublisher<AuthenticationState, Error> {
        Result {
            URLRequest.respondToChallenge(serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt, response: response)
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
                    case 400, 401:
                        throw AuthenticationError.incorrectSecurityCode
                    case 412:
                        throw AuthenticationError.appleIDAndPrivacyAcknowledgementRequired
                    case let code:
                        throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
                    }
                }
                .flatMap { (data, response) -> AnyPublisher<AuthenticationState, Error> in
                    self.updateSession(serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
                }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Session
    
    /// Use the olympus session endpoint to see if the existing session is still valid
    public func validateSession() -> AnyPublisher<Void, Error> {
        return Current.network.dataTask(with: URLRequest.olympusSession)
            .tryMap { result -> Data in
                let httpResponse = result.response as! HTTPURLResponse
                if httpResponse.statusCode == 401 {
                    throw AuthenticationError.notAuthorized
                }

                return result.data
            }
            .decode(type: AppleSession.self, decoder: JSONDecoder())
            .tryMap { session in
                // A user that is a non-paid Apple Developer will have a provider == nil
                // Those users can still download Xcode.
                // Non Apple Developers will get caught in the download as invalid
//                if session.provider == nil {
//                    throw AuthenticationError.notDeveloperAppleId
//                }
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

    func sha256(data : Data) -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    private func pbkdf2(password: String, saltData: Data, keyByteCount: Int, prf: CCPseudoRandomAlgorithm, rounds: Int, protocol srpProtocol: SRPProtocol) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        let hashedPasswordDataRaw = sha256(data: passwordData)
        let hashedPasswordData = switch srpProtocol {
        case .s2k: hashedPasswordDataRaw
        // the legacy s2k_fo protocol requires hex-encoding the digest before performing PBKDF2.
        case .s2k_fo: Data(hashedPasswordDataRaw.hexEncodedString().lowercased().utf8)
        }

        var derivedKeyData = Data(repeating: 0, count: keyByteCount)
        let derivedCount = derivedKeyData.count
        let derivationStatus: Int32 = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            let keyBuffer: UnsafeMutablePointer<UInt8> =
                derivedKeyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return saltData.withUnsafeBytes { saltBytes -> Int32 in
                let saltBuffer: UnsafePointer<UInt8> = saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return hashedPasswordData.withUnsafeBytes { hashedPasswordBytes -> Int32 in
                    let passwordBuffer: UnsafePointer<UInt8> = hashedPasswordBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer,
                        hashedPasswordData.count,
                        saltBuffer,
                        saltData.count,
                        prf,
                        UInt32(rounds),
                        keyBuffer,
                        derivedCount)
                }
            }
        }
        return derivationStatus == kCCSuccess ? derivedKeyData : nil
    }

}

// MARK: - Types

public enum AuthenticationState: Equatable {
    case unauthenticated
    case waitingForSecondFactor(TwoFactorOption, AuthOptionsResponse, AppleSessionData)
    case authenticated
    case notAppleDeveloper
}

public enum AuthenticationError: Swift.Error, LocalizedError, Equatable {
    case invalidSession
    case invalidHashcash
    case invalidUsernameOrPassword(username: String)
    case incorrectSecurityCode
    case unexpectedSignInResponse(statusCode: Int, message: String?)
    case appleIDAndPrivacyAcknowledgementRequired
    case accountUsesTwoStepAuthentication
    case accountUsesUnknownAuthenticationKind(String?)
    case accountLocked(String)
    case badStatusCode(statusCode: Int, data: Data, response: HTTPURLResponse)
    case notDeveloperAppleId
    case notAuthorized
    case invalidResult(resultString: String?)
    case srpInvalidPublicKey
    
    public var errorDescription: String? {
        switch self {
        case .invalidSession:
            return "Your authentication session is invalid. Try signing in again."
        case .invalidHashcash:
            return "Could not create a hashcash for the session."
        case .invalidUsernameOrPassword:
            return "Invalid username and password combination."
        case .incorrectSecurityCode:
            return "The code that was entered is incorrect."
        case let .unexpectedSignInResponse(statusCode, message):
            return """
                Received an unexpected sign in response. If you continue to have problems, please submit a bug report in the Help menu and include the following information:

                Status code: \(statusCode)
                \(message != nil ? ("Message: " + message!) : "")
                """
        case .appleIDAndPrivacyAcknowledgementRequired:
            return "You must sign in to https://appstoreconnect.apple.com and acknowledge the Apple ID & Privacy agreement."
        case .accountUsesTwoStepAuthentication:
            return "Received a response from Apple that indicates this account has two-step authentication enabled. xcodes currently only supports the newer two-factor authentication, though. Please consider upgrading to two-factor authentication, or explain why this isn't an option for you by making a new feature request in the Help menu."
        case .accountUsesUnknownAuthenticationKind:
            return "Received a response from Apple that indicates this account has two-step or two-factor authentication enabled, but xcodes is unsure how to handle this response. If you continue to have problems, please submit a bug report in the Help menu."
        case let .accountLocked(message):
            return message
        case let .badStatusCode(statusCode, _, _):
            return "Received an unexpected status code: \(statusCode). If you continue to have problems, please submit a bug report in the Help menu."
        case .notDeveloperAppleId:
            return "You are not registered as an Apple Developer.  Please visit Apple Developer Registration. https://developer.apple.com/register/"
        case .notAuthorized:
            return "You are not authorized. Please Sign in with your Apple ID first."
        case let .invalidResult(resultString):
            return resultString ?? "If you continue to have problems, please submit a bug report in the Help menu."
        case .srpInvalidPublicKey:
            return "Invalid Key"
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
    case securityKey
}

public struct FSAChallenge: Equatable, Decodable {
    public let challenge: String
    public let keyHandles: [String]
    public let allowedCredentials: String
}

public struct AuthOptionsResponse: Equatable, Decodable {
    public let trustedPhoneNumbers: [TrustedPhoneNumber]?
    public let trustedDevices: [TrustedDevice]?
    public let securityCode: SecurityCodeInfo?
    public let noTrustedDevices: Bool?
    public let serviceErrors: [ServiceError]?
    public let fsaChallenge: FSAChallenge?
    
    public init(
        trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]?, 
        trustedDevices: [AuthOptionsResponse.TrustedDevice]?, 
        securityCode: AuthOptionsResponse.SecurityCodeInfo, 
        noTrustedDevices: Bool? = nil, 
        serviceErrors: [ServiceError]? = nil,
        fsaChallenge: FSAChallenge? = nil
    ) {
        self.trustedPhoneNumbers = trustedPhoneNumbers
        self.trustedDevices = trustedDevices
        self.securityCode = securityCode
        self.noTrustedDevices = noTrustedDevices
        self.serviceErrors = serviceErrors
        self.fsaChallenge = fsaChallenge
    }
    
    public var kind: Kind {
        if trustedDevices != nil {
            return .twoStep
        } else if trustedPhoneNumbers != nil {
            return .twoFactor
        } else if fsaChallenge != nil {
            return .securityKey
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
        case twoStep, twoFactor, securityKey, unknown
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

/// Object returned from olympus/v1/session
/// Used to check Provider, and show name
/// If Provider is nil, we can assume the Apple User is NOT an Apple Developer and can't download Xcode.
public struct AppleSession: Decodable, Equatable {
    public let user: AppleUser
    public let provider: AppleProvider?
}

public struct AppleProvider: Decodable, Equatable {
    public let providerId: Int
    public let name: String
}

public struct AppleUser: Decodable, Equatable {
    public let fullName: String
}

public struct ServerSRPInitResponse: Decodable {
    let iteration: Int
    let salt: String
    let b: String
    let c: String
    let `protocol`: SRPProtocol
}



extension String {
    func base64ToU8Array() -> Data {
        return Data(base64Encoded: self) ?? Data()
    }
}
extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
