import Foundation

extension URL {
    static let itcServiceKey = URL(string: "https://appstoreconnect.apple.com/olympus/v1/app/config?hostname=itunesconnect.apple.com")!
    static let signIn = URL(string: "https://idmsa.apple.com/appleauth/auth/signin")!
    static let authOptions = URL(string: "https://idmsa.apple.com/appleauth/auth")!
    static let requestSecurityCode = URL(string: "https://idmsa.apple.com/appleauth/auth/verify/phone")!
    static func submitSecurityCode(_ code: SecurityCode) -> URL { URL(string: "https://idmsa.apple.com/appleauth/auth/verify/\(code.urlPathComponent)/securitycode")! }
    static let trust = URL(string: "https://idmsa.apple.com/appleauth/auth/2sv/trust")!
    static let olympusSession = URL(string: "https://appstoreconnect.apple.com/olympus/v1/session")!
}

extension URLRequest {
    static var itcServiceKey: URLRequest {
        return URLRequest(url: .itcServiceKey)
    }

    static func signIn(serviceKey: String, accountName: String, password: String) -> URLRequest {
        struct Body: Encodable {
            let accountName: String
            let password: String
            let rememberMe = true
        }

        var request = URLRequest(url: .signIn)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Requested-With"] = "XMLHttpRequest"
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["Accept"] = "application/json, text/javascript"
        request.httpMethod = "POST"
        request.httpBody = try! JSONEncoder().encode(Body(accountName: accountName, password: password))
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
    
    static func requestSecurityCode(serviceKey: String, sessionID: String, scnt: String, trustedPhoneID: Int) throws -> URLRequest {
        struct Body: Encodable {
            let phoneNumber: PhoneNumber
            let mode = "sms"
            
            struct PhoneNumber: Encodable {
                let id: Int
            }
        }
        
        var request = URLRequest(url: .requestSecurityCode)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["accept"] = "application/json"
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(Body(phoneNumber: .init(id: trustedPhoneID)))
        return request
    }

    static func submitSecurityCode(serviceKey: String, sessionID: String, scnt: String, code: SecurityCode) throws -> URLRequest {
        struct DeviceSecurityCodeRequest: Encodable {
            let securityCode: SecurityCode
            
            struct SecurityCode: Encodable {
                let code: String
            }
        }

        struct SMSSecurityCodeRequest: Encodable {
            let securityCode: SecurityCode
            let phoneNumber: PhoneNumber
            let mode = "sms"
            
            struct SecurityCode: Encodable {
                let code: String
            }
            struct PhoneNumber: Encodable {
                let id: Int
            }
        }

        var request = URLRequest(url: .submitSecurityCode(code))
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.httpMethod = "POST"
        switch code {
        case .device(let code):
            request.httpBody = try JSONEncoder().encode(DeviceSecurityCodeRequest(securityCode: .init(code: code)))
        case .sms(let code, let phoneNumberId):
            request.httpBody = try JSONEncoder().encode(SMSSecurityCodeRequest(securityCode: .init(code: code), phoneNumber: .init(id: phoneNumberId)))
        }
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
        return URLRequest(url: .olympusSession)
    }
}
