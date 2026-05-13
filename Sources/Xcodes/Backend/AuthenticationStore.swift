import AppleAPI
import Foundation
import Observation
import os.log
import XcodesKit

@MainActor
protocol AuthenticationClient {
    func signIn(accountName: String, password: String) async throws -> AuthenticationState
    func requestSMS(
        to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber,
        authOptions: AuthOptionsResponse,
        sessionData: AppleSessionData
    ) async throws -> AuthenticationState
    func submitSecurityCode(_ code: SecurityCode, sessionData: AppleSessionData) async throws -> AuthenticationState
}

struct AppleAuthenticationClient: AuthenticationClient {
    private let client = AppleAPI.Client()

    func signIn(accountName: String, password: String) async throws -> AuthenticationState {
        try await client.srpLogin(accountName: accountName, password: password)
    }

    func requestSMS(
        to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber,
        authOptions: AuthOptionsResponse,
        sessionData: AppleSessionData
    ) async throws -> AuthenticationState {
        try await client.requestSMSSecurityCode(
            to: trustedPhoneNumber,
            authOptions: authOptions,
            sessionData: sessionData
        )
    }

    func submitSecurityCode(_ code: SecurityCode, sessionData: AppleSessionData) async throws -> AuthenticationState {
        try await client.submitSecurityCode(code, sessionData: sessionData)
    }
}

@MainActor
@Observable
final class AuthenticationStore {
    typealias SecondFactorHandler = @MainActor (TwoFactorOption, AuthOptionsResponse, AppleSessionData) -> Void
    typealias AuthenticationStateHandler = @MainActor (AuthenticationState) -> Void

    var authenticationState: AuthenticationState = .unauthenticated {
        didSet {
            onAuthenticationStateChanged?(authenticationState)
        }
    }

    var isProcessingAuthRequest = false
    var authError: Error?

    @ObservationIgnored nonisolated(unsafe) var onSecondFactorRequired: SecondFactorHandler?
    @ObservationIgnored nonisolated(unsafe) var onAuthenticationStateChanged: AuthenticationStateHandler?

    @ObservationIgnored private nonisolated(unsafe) let client: AuthenticationClient

    nonisolated init(client: AuthenticationClient = AppleAuthenticationClient()) {
        self.client = client
    }

    var savedUsername: String? {
        current.defaults.string(forKey: "username")
    }

    var hasSavedUsername: Bool {
        savedUsername != nil
    }

    func validateADCSession(path: String) async throws {
        let result = try await current.network.dataTaskAsync(with: URLRequest.downloadADCAuth(path: path))
        guard let httpResponse = result.1 as? HTTPURLResponse else {
            throw AuthenticationError.invalidSession
        }
        if httpResponse.statusCode == 401 {
            throw AuthenticationError.notAuthorized
        }
    }

    func validateSession() async throws {
        try await current.network.validateSessionAsync()
    }

    func signInIfNeeded() async throws {
        do {
            try await validateSession()
        } catch {
            guard
                let username = savedUsername,
                let password = try? current.keychain.getString(username)
            else {
                throw error
            }

            let state = try await signIn(username: username, password: password)
            try await handleTerminalAuthenticationState(state.isTerminal ? state : waitForTerminalAuthenticationState())
        }
    }

    @discardableResult
    func signIn(username: String, password: String) async throws -> AuthenticationState {
        authError = nil
        try? current.keychain.set(password, key: username)
        current.defaults.set(username, forKey: "username")

        return try await runAuthenticationRequest {
            try await client.signIn(accountName: username.lowercased(), password: password)
        }
    }

    func signIn(username: String, password: String) {
        Task {
            do {
                _ = try await signIn(username: username, password: password)
            } catch {
                handleAuthenticationError(error)
            }
        }
    }

    func handleTwoFactorOption(
        _ option: TwoFactorOption,
        authOptions: AuthOptionsResponse,
        serviceKey: String,
        sessionID: String,
        scnt: String
    ) {
        let sessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        onSecondFactorRequired?(option, authOptions, sessionData)
    }

    func requestSMS(
        to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber,
        authOptions: AuthOptionsResponse,
        sessionData: AppleSessionData
    ) {
        Task {
            do {
                _ = try await runAuthenticationRequest {
                    try await client.requestSMS(
                        to: trustedPhoneNumber,
                        authOptions: authOptions,
                        sessionData: sessionData
                    )
                }
            } catch {
                handleAuthenticationError(error)
            }
        }
    }

    func choosePhoneNumberForSMS(authOptions: AuthOptionsResponse, sessionData: AppleSessionData) {
        onSecondFactorRequired?(.smsPendingChoice, authOptions, sessionData)
    }

    func submitSecurityCode(_ code: SecurityCode, sessionData: AppleSessionData) {
        Task {
            do {
                _ = try await runAuthenticationRequest {
                    try await client.submitSecurityCode(code, sessionData: sessionData)
                }
            } catch {
                handleAuthenticationError(error)
            }
        }
    }

    func signOut() {
        clearLoginCredentials()
        AppleAPI.current.network.session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
        authenticationState = .unauthenticated
    }

    private func runAuthenticationRequest(_ request: () async throws -> AuthenticationState) async throws
        -> AuthenticationState {
        isProcessingAuthRequest = true
        defer { isProcessingAuthRequest = false }

        do {
            let state = try await request()
            authenticationState = state
            handleAuthenticationState(state)
            return state
        } catch {
            handleAuthenticationError(error)
            throw error
        }
    }

    private func handleAuthenticationState(_ state: AuthenticationState) {
        if case let .waitingForSecondFactor(option, authOptions, sessionData) = state {
            handleTwoFactorOption(
                option,
                authOptions: authOptions,
                serviceKey: sessionData.serviceKey,
                sessionID: sessionData.sessionID,
                scnt: sessionData.scnt
            )
        }
    }

    private func handleTerminalAuthenticationState(_ state: AuthenticationState) throws {
        if state == .unauthenticated {
            throw AuthenticationError.invalidSession
        }
        if state == .notAppleDeveloper {
            throw AuthenticationError.notDeveloperAppleId
        }
    }

    private func handleAuthenticationError(_ error: Error) {
        clearLoginCredentials()
        Logger.appState.error("Authentication error: \(error.legibleDescription)")
        authError = error
    }

    private func waitForTerminalAuthenticationState() async -> AuthenticationState {
        while !authenticationState.isTerminal {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return authenticationState
    }

    private func clearLoginCredentials() {
        if let username = savedUsername {
            try? current.keychain.remove(username)
        }
        current.defaults.removeObject(forKey: "username")
    }
}

private extension AuthenticationState {
    var isTerminal: Bool {
        switch self {
        case .authenticated, .unauthenticated, .notAppleDeveloper:
            true
        case .waitingForSecondFactor:
            false
        }
    }
}
