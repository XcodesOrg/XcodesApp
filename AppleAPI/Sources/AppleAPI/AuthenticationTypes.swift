import Foundation
import SRP

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
    case accountUsesSecurityKeyAuthentication
    case accountUsesUnknownAuthenticationKind(String?)
    case missingTrustedPhoneNumber
    case accountLocked(String)
    case badStatusCode(statusCode: Int, data: Data, response: HTTPURLResponse)
    case notDeveloperAppleId
    case notAuthorized
    case invalidResult(resultString: String?)
    case srpInvalidPublicKey

    public var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Your authentication session is invalid. Try signing in again."
        case .invalidHashcash:
            "Could not create a hashcash for the session."
        case .invalidUsernameOrPassword:
            "Invalid username and password combination."
        case .incorrectSecurityCode:
            "The code that was entered is incorrect."
        case let .unexpectedSignInResponse(statusCode, message):
            // swiftlint:disable line_length
            """
            Received an unexpected sign in response. If you continue to have problems, please submit a bug report in the Help menu and include the following information:

            Status code: \(statusCode)
            \(message.map { "Message: \($0)" } ?? "")
            """
            // swiftlint:enable line_length
        case .appleIDAndPrivacyAcknowledgementRequired:
            "You must sign in to https://appstoreconnect.apple.com and acknowledge the Apple ID & Privacy agreement."
        case .accountUsesTwoStepAuthentication:
            // swiftlint:disable:next line_length
            "Received a response from Apple that indicates this account has two-step authentication enabled. rhodon currently only supports the newer two-factor authentication, though. Please consider upgrading to two-factor authentication, or explain why this isn't an option for you by making a new feature request in the Help menu."
        case .accountUsesSecurityKeyAuthentication:
            // swiftlint:disable:next line_length
            "This Apple ID requires physical security-key authentication, which Rhodon does not support. Use Apple's passkey-capable sign-in flow outside Rhodon, or sign in with a trusted device code or SMS verification instead."
        case .accountUsesUnknownAuthenticationKind:
            // swiftlint:disable:next line_length
            "Received a response from Apple that indicates this account has two-step or two-factor authentication enabled, but rhodon is unsure how to handle this response. If you continue to have problems, please submit a bug report in the Help menu."
        case .missingTrustedPhoneNumber:
            "Received a two-factor authentication response from Apple without a trusted phone number."
        case let .accountLocked(message):
            message
        case let .badStatusCode(statusCode, _, _):
            // swiftlint:disable:next line_length
            "Received an unexpected status code: \(statusCode). If you continue to have problems, please submit a bug report in the Help menu."
        case .notDeveloperAppleId:
            // swiftlint:disable:next line_length
            "You are not registered as an Apple Developer. Please visit Apple Developer Registration. https://developer.apple.com/register/"
        case .notAuthorized:
            "You are not authorized. Please Sign in with your Apple ID first."
        case let .invalidResult(resultString):
            resultString ?? "If you continue to have problems, please submit a bug report in the Help menu."
        case .srpInvalidPublicKey:
            "Invalid Key"
        }
    }
}

public struct AppleSessionData: Equatable, Identifiable {
    public let serviceKey: String
    public let sessionID: String
    public let scnt: String

    public var id: String {
        sessionID
    }

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
            "\(code): \(message)"
        }
    }
}

public enum TwoFactorOption: Equatable {
    case smsSent(AuthOptionsResponse.TrustedPhoneNumber)
    case codeSent
    case smsPendingChoice
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
            .twoStep
        } else if trustedPhoneNumbers != nil {
            .twoFactor
        } else if fsaChallenge != nil {
            .securityKey
        } else {
            .unknown
        }
    }

    /// One time with a new testing account I had a response where noTrustedDevices was nil, but the account didn't have
    /// any trusted devices.
    /// This should have been a situation where an SMS security code was sent automatically.
    /// This resolved itself either after some time passed, or by signing into appleid.apple.com with the account.
    /// Not sure if it's worth explicitly handling this case or if it'll be really rare.
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
        case .device: "trusteddevice"
        case .sms: "phone"
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
    let serverPublicKey: String
    let challenge: String
    let `protocol`: SRPProtocol

    enum CodingKeys: String, CodingKey {
        case iteration
        case salt
        case serverPublicKey = "b"
        case challenge = "c"
        case `protocol`
    }
}

extension String {
    func base64ToU8Array() -> Data {
        Data(base64Encoded: self) ?? Data()
    }
}

extension Data {
    func hexEncodedString() -> String {
        map {
            let hex = String($0, radix: 16)
            return hex.count == 1 ? "0\(hex)" : hex
        }.joined()
    }
}
