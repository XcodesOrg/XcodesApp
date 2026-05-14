import AppleAPI
@testable import Rhodon
import XCTest

@MainActor
final class AuthenticationStoreTests: XCTestCase {
    private final class MockBrowserAuthenticationClient: BrowserAuthenticationClient {
        var signInResult: Result<AuthenticationState, Error> = .success(.authenticated)
        private(set) var receivedCookies: [HTTPCookie] = []

        func signIn(with cookies: [HTTPCookie]) async throws -> AuthenticationState {
            receivedCookies = cookies
            return try signInResult.get()
        }
    }

    private final class MockLegacyAuthenticationClient: LegacyAuthenticationClient {
        var signInResult: Result<AuthenticationState, Error> = .success(.authenticated)
        private(set) var receivedAccountName: String?
        private(set) var receivedPassword: String?

        func signIn(accountName: String, password: String) async throws -> AuthenticationState {
            receivedAccountName = accountName
            receivedPassword = password
            return try signInResult.get()
        }

        func requestSMS(
            to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber,
            authOptions: AuthOptionsResponse,
            sessionData: AppleSessionData
        ) async throws -> AuthenticationState {
            .waitingForSecondFactor(.smsSent(trustedPhoneNumber), authOptions, sessionData)
        }

        func submitSecurityCode(_: SecurityCode, sessionData _: AppleSessionData) async throws -> AuthenticationState {
            .authenticated
        }
    }

    override func setUpWithError() throws {
        current = .mock
    }

    func testSignInStoresCredentialsAndUpdatesAuthenticationState() async throws {
        let browserClient = MockBrowserAuthenticationClient()
        let client = MockLegacyAuthenticationClient()
        var storedUsername: String?
        var storedPassword: String?

        current.defaults.set = { value, key in
            if key == "username" {
                storedUsername = value as? String
            }
        }
        current.keychain.set = { password, username in
            storedPassword = "\(username):\(password)"
        }

        let subject = AuthenticationStore(browserClient: browserClient, legacyClient: client)

        let state = try await subject.signIn(username: "USER@ICLOUD.COM", password: "secret")

        XCTAssertEqual(state, .authenticated)
        XCTAssertEqual(subject.authenticationState, .authenticated)
        XCTAssertEqual(client.receivedAccountName, "user@icloud.com")
        XCTAssertEqual(client.receivedPassword, "secret")
        XCTAssertEqual(storedUsername, "USER@ICLOUD.COM")
        XCTAssertEqual(storedPassword, "USER@ICLOUD.COM:secret")
    }

    func testSignInFailureClearsSavedCredentialsAndPublishesAuthError() async {
        let browserClient = MockBrowserAuthenticationClient()
        let client = MockLegacyAuthenticationClient()
        client.signInResult = .failure(AuthenticationError.invalidUsernameOrPassword(username: "user@icloud.com"))

        var removedKeychainAccount: String?
        var removedDefaultsKey: String?

        current.defaults.string = { key in
            key == "username" ? "user@icloud.com" : nil
        }
        current.defaults.removeObject = { key in
            removedDefaultsKey = key
        }
        current.keychain.remove = { username in
            removedKeychainAccount = username
        }

        let subject = AuthenticationStore(browserClient: browserClient, legacyClient: client)

        do {
            _ = try await subject.signIn(username: "user@icloud.com", password: "wrong")
            XCTFail("Expected sign in to fail")
        } catch {
            XCTAssertEqual(removedKeychainAccount, "user@icloud.com")
            XCTAssertEqual(removedDefaultsKey, "username")
            XCTAssertNotNil(subject.authError)
        }
    }

    func testBrowserSignInClearsSavedCredentialsAndUpdatesAuthenticationState() async throws {
        let browserClient = MockBrowserAuthenticationClient()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: ".apple.com",
            .path: "/",
            .name: "myacinfo",
            .value: "browser-session"
        ]))

        var removedKeychainAccount: String?
        var removedDefaultsKey: String?

        current.defaults.string = { key in
            key == "username" ? "user@icloud.com" : nil
        }
        current.defaults.removeObject = { key in
            removedDefaultsKey = key
        }
        current.keychain.remove = { username in
            removedKeychainAccount = username
        }

        let subject = AuthenticationStore(browserClient: browserClient, legacyClient: nil)

        let state = try await subject.signInWithBrowser(cookies: [cookie])

        XCTAssertEqual(state, .authenticated)
        XCTAssertEqual(subject.authenticationState, .authenticated)
        XCTAssertEqual(browserClient.receivedCookies, [cookie])
        XCTAssertEqual(removedKeychainAccount, "user@icloud.com")
        XCTAssertEqual(removedDefaultsKey, "username")
    }
}
