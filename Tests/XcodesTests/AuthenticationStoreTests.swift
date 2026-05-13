import AppleAPI
@testable import Xcodes
import XCTest

@MainActor
final class AuthenticationStoreTests: XCTestCase {
    private final class MockAuthenticationClient: AuthenticationClient {
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
        let client = MockAuthenticationClient()
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

        let subject = AuthenticationStore(client: client)

        let state = try await subject.signIn(username: "USER@ICLOUD.COM", password: "secret")

        XCTAssertEqual(state, .authenticated)
        XCTAssertEqual(subject.authenticationState, .authenticated)
        XCTAssertEqual(client.receivedAccountName, "user@icloud.com")
        XCTAssertEqual(client.receivedPassword, "secret")
        XCTAssertEqual(storedUsername, "USER@ICLOUD.COM")
        XCTAssertEqual(storedPassword, "USER@ICLOUD.COM:secret")
    }

    func testSignInFailureClearsSavedCredentialsAndPublishesAuthError() async {
        let client = MockAuthenticationClient()
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

        let subject = AuthenticationStore(client: client)

        do {
            _ = try await subject.signIn(username: "user@icloud.com", password: "wrong")
            XCTFail("Expected sign in to fail")
        } catch {
            XCTAssertEqual(removedKeychainAccount, "user@icloud.com")
            XCTAssertEqual(removedDefaultsKey, "username")
            XCTAssertNotNil(subject.authError)
        }
    }
}
