import Foundation

public extension URL {
    static let itcServiceKey =
        URL(string: "https://appstoreconnect.apple.com/olympus/v1/app/config?hostname=itunesconnect.apple.com")!
    static let signIn = URL(string: "https://idmsa.apple.com/appleauth/auth/signin")!
    static let authOptions = URL(string: "https://idmsa.apple.com/appleauth/auth")!
    static let requestSecurityCode = URL(string: "https://idmsa.apple.com/appleauth/auth/verify/phone")!
    static func submitSecurityCode(_ code: SecurityCode)
        -> URL {
        URL(string: "https://idmsa.apple.com/appleauth/auth/verify/\(code.urlPathComponent)/securitycode")!
    }

    static let trust = URL(string: "https://idmsa.apple.com/appleauth/auth/2sv/trust")!
    static let federate = URL(string: "https://idmsa.apple.com/appleauth/auth/federate")!
    static let olympusSession = URL(string: "https://appstoreconnect.apple.com/olympus/v1/session")!
    static let keyAuth = URL(string: "https://idmsa.apple.com/appleauth/auth/verify/security/key")!

    static let srpInit = URL(string: "https://idmsa.apple.com/appleauth/auth/signin/init")!
    static let srpComplete =
        URL(string: "https://idmsa.apple.com/appleauth/auth/signin/complete?isRememberMeEnabled=false")!
}

private struct SignInRequestBody: Encodable {
    let accountName: String
    let password: String
    let rememberMe = true
}

private struct TrustedPhoneNumberRequestBody: Encodable {
    let phoneNumber: PhoneNumberRequestBody
    let mode = "sms"
}

private struct PhoneNumberRequestBody: Encodable {
    let id: Int
}

private struct DeviceSecurityCodeRequestBody: Encodable {
    let securityCode: SecurityCodeRequestBody
}

private struct SMSSecurityCodeRequestBody: Encodable {
    let securityCode: SecurityCodeRequestBody
    let phoneNumber: PhoneNumberRequestBody
    let mode = "sms"
}

private struct SecurityCodeRequestBody: Encodable {
    let code: String
}

private struct ServerSRPInitRequestBody: Encodable {
    public let publicKey: String
    public let accountName: String
    public let protocols: [SRPProtocol]

    enum CodingKeys: String, CodingKey {
        case publicKey = "a"
        case accountName
        case protocols
    }
}

struct SRPCompletePayload: Encodable {
    let accountName: String
    let challenge: String
    let clientProof: String
    let serverProof: String
    let rememberMe = false

    enum CodingKeys: String, CodingKey {
        case accountName
        case challenge = "c"
        case clientProof = "m1"
        case serverProof = "m2"
        case rememberMe
    }
}

public extension URLRequest {
    static var itcServiceKey: URLRequest {
        URLRequest(url: .itcServiceKey)
    }

    static func signIn(
        serviceKey: String,
        accountName: String,
        password: String,
        hashcash: String
    ) throws -> URLRequest {
        var request = URLRequest(url: .signIn)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Requested-With"] = "XMLHttpRequest"
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["X-Apple-HC"] = hashcash
        request.allHTTPHeaderFields?["Accept"] = "application/json, text/javascript"
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(SignInRequestBody(accountName: accountName, password: password))
        return request
    }

    static func authOptions(serviceKey: String, sessionID: String, scnt: String) -> URLRequest {
        var request = URLRequest(url: .authOptions)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["accept"] = "application/json"
        return request
    }

    static func requestSecurityCode(
        serviceKey: String,
        sessionID: String,
        scnt: String,
        trustedPhoneID: Int
    ) throws -> URLRequest {
        var request = URLRequest(url: .requestSecurityCode)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["accept"] = "application/json"
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(TrustedPhoneNumberRequestBody(
            phoneNumber: .init(id: trustedPhoneID)
        ))
        return request
    }

    static func submitSecurityCode(
        serviceKey: String,
        sessionID: String,
        scnt: String,
        code: SecurityCode
    ) throws -> URLRequest {
        var request = URLRequest(url: .submitSecurityCode(code))
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.httpMethod = "POST"
        switch code {
        case let .device(code):
            request.httpBody = try JSONEncoder().encode(DeviceSecurityCodeRequestBody(
                securityCode: .init(code: code)
            ))
        case let .sms(code, phoneNumberId):
            request.httpBody = try JSONEncoder().encode(SMSSecurityCodeRequestBody(
                securityCode: .init(code: code),
                phoneNumber: .init(id: phoneNumberId)
            ))
        }
        return request
    }

    static func respondToChallenge(serviceKey: String, sessionID: String, scnt: String, response: Data) -> URLRequest {
        var request = URLRequest(url: .keyAuth)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.httpMethod = "POST"
        request.httpBody = response
        return request
    }

    static func trust(serviceKey: String, sessionID: String, scnt: String) -> URLRequest {
        var request = URLRequest(url: .trust)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        return request
    }

    static var olympusSession: URLRequest {
        URLRequest(url: .olympusSession)
    }

    static func federate(account _: String, serviceKey _: String) throws -> URLRequest {
        struct FederateRequest: Encodable {
            let accountName: String
            let rememberMe: Bool
        }
        var request = URLRequest(url: .signIn)
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.httpMethod = "GET"

//        let encoder = JSONEncoder()
//        encoder.outputFormatting = .withoutEscapingSlashes
//        request.httpBody = try encoder.encode(FederateRequest(accountName: account, rememberMe: true))

        return request
    }

    static func SRPInit(serviceKey: String, publicKey: String, accountName: String) -> URLRequest {
        var request = URLRequest(url: .srpInit)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Requested-With"] = "XMLHttpRequest"
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey

        request.httpBody = try? JSONEncoder().encode(ServerSRPInitRequestBody(
            publicKey: publicKey,
            accountName: accountName,
            protocols: [.s2k, .s2kFo]
        ))
        return request
    }

    internal static func SRPComplete(
        serviceKey: String,
        hashcash: String,
        payload: SRPCompletePayload
    ) -> URLRequest {
        var request = URLRequest(url: .srpComplete)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Requested-With"] = "XMLHttpRequest"
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["X-Apple-HC"] = hashcash

        request.httpBody = try? JSONEncoder().encode(payload)
        return request
    }
}

public enum SRPProtocol: String, Codable {
    case s2k
    case s2kFo = "s2k_fo"
}
