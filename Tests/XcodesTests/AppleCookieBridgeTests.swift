import AppleAPI
import Foundation
@testable import Xcodes
import XCTest

final class AppleCookieBridgeTests: XCTestCase {
    private final class MockCookieStorage: CookieStoring {
        var cookies: [HTTPCookie]?
        private(set) var deletedCookies: [HTTPCookie] = []

        init(cookies: [HTTPCookie] = []) {
            self.cookies = cookies
        }

        func setCookie(_ cookie: HTTPCookie) {
            cookies = (cookies ?? []) + [cookie]
        }

        func deleteCookie(_ cookie: HTTPCookie) {
            deletedCookies.append(cookie)
            cookies?.removeAll { $0 == cookie }
        }
    }

    func testReplaceAppleCookiesKeepsNonAppleCookies() throws {
        let oldAppleCookie = try cookie(name: "old", domain: ".apple.com", value: "old-value")
        let oldNonAppleCookie = try cookie(name: "other", domain: "example.com", value: "other-value")
        let newAppleCookie = try cookie(name: "new", domain: "developer.apple.com", value: "new-value")
        let newNonAppleCookie = try cookie(name: "ignored", domain: "example.com", value: "ignored-value")
        let storage = MockCookieStorage(cookies: [oldAppleCookie, oldNonAppleCookie])

        AppleCookieBridge(cookieStorage: storage).replaceAppleCookies(with: [newAppleCookie, newNonAppleCookie])

        XCTAssertEqual(storage.deletedCookies, [oldAppleCookie])
        XCTAssertEqual(storage.cookies, [oldNonAppleCookie, newAppleCookie])
    }

    func testIsAppleCookieAcceptsAppleSubdomains() throws {
        XCTAssertTrue(AppleCookieBridge.isAppleCookie(try cookie(name: "a", domain: ".apple.com")))
        XCTAssertTrue(AppleCookieBridge.isAppleCookie(try cookie(name: "b", domain: "idmsa.apple.com")))
        XCTAssertTrue(AppleCookieBridge.isAppleCookie(try cookie(name: "c", domain: "developer.apple.com")))
        XCTAssertFalse(AppleCookieBridge.isAppleCookie(try cookie(name: "d", domain: "notapple.com")))
        XCTAssertFalse(AppleCookieBridge.isAppleCookie(try cookie(name: "e", domain: "apple.com.example.com")))
    }

    func testBrowserAuthenticationClientImportsCookiesAndValidatesSession() async throws {
        let storage = MockCookieStorage()
        let appleCookie = try cookie(name: "myacinfo", domain: ".apple.com")
        let nonAppleCookie = try cookie(name: "ignored", domain: "example.com")
        var didValidateSession = false
        let subject = AppleBrowserAuthenticationClient(
            cookieStorage: storage,
            validateSession: {
                didValidateSession = true
            }
        )

        let state = try await subject.signIn(with: [appleCookie, nonAppleCookie])

        XCTAssertEqual(state, .authenticated)
        XCTAssertEqual(storage.cookies, [appleCookie])
        XCTAssertTrue(didValidateSession)
    }

    private func cookie(name: String, domain: String, value: String = "value") throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value
        ]))
    }
}
