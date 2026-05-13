import AppleAPI
import Foundation

protocol BrowserAuthenticationClient {
    func signIn(with cookies: [HTTPCookie]) async throws -> AuthenticationState
}

struct AppleBrowserAuthenticationClient: BrowserAuthenticationClient {
    private let cookieStorage: (any CookieStoring)?
    private let validateSession: () async throws -> Void

    init(
        cookieStorage: (any CookieStoring)? = AppleAPI.current.network.session.configuration.httpCookieStorage,
        validateSession: @escaping () async throws -> Void = { try await current.network.validateSessionAsync() }
    ) {
        self.cookieStorage = cookieStorage
        self.validateSession = validateSession
    }

    func signIn(with cookies: [HTTPCookie]) async throws -> AuthenticationState {
        guard let cookieStorage else {
            throw AuthenticationError.invalidSession
        }

        AppleCookieBridge(cookieStorage: cookieStorage).replaceAppleCookies(with: cookies)
        try await validateSession()
        return .authenticated
    }
}

protocol CookieStoring: AnyObject {
    var cookies: [HTTPCookie]? { get }

    func setCookie(_ cookie: HTTPCookie)
    func deleteCookie(_ cookie: HTTPCookie)
}

extension HTTPCookieStorage: CookieStoring {}

struct AppleCookieBridge {
    private let cookieStorage: any CookieStoring

    init(cookieStorage: any CookieStoring) {
        self.cookieStorage = cookieStorage
    }

    func replaceAppleCookies(with cookies: [HTTPCookie]) {
        cookieStorage.cookies?
            .filter(Self.isAppleCookie)
            .forEach(cookieStorage.deleteCookie)

        cookies
            .filter(Self.isAppleCookie)
            .forEach(cookieStorage.setCookie)
    }

    static func isAppleCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        return domain == "apple.com" || domain.hasSuffix(".apple.com")
    }
}
