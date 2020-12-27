import AppKit
import AppleAPI
import Combine
import Path
import LegibleError
import KeychainAccess
import SwiftUI
import Version

class AppState: ObservableObject {
    private let client = AppleAPI.Client()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var availableXcodes: [AvailableXcode] = [] {
        willSet {
            updateAllXcodes(newValue)
        }
    }
    var allXcodes: [Xcode] = []
    @Published var updatePublisher: AnyCancellable?
    var isUpdating: Bool { updatePublisher != nil }
    @Published var error: AlertContent?
    @Published var authError: AlertContent?
    @Published var presentingSignInAlert = false
    @Published var isProcessingAuthRequest = false
    @Published var secondFactorData: SecondFactorData?
    @Published var xcodeBeingConfirmedForUninstallation: Xcode?
    
    init() {
        try? loadCachedAvailableXcodes()
    }
    
    // MARK: - Authentication
    
    func validateSession() -> AnyPublisher<Void, Error> {
        return client.validateSession()
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveCompletion: { completion in 
                if case .failure = completion {
                    self.authenticationState = .unauthenticated
                    self.presentingSignInAlert = true
                }
            })
            .eraseToAnyPublisher()
    }
    
    func signInIfNeeded() -> AnyPublisher<Void, Error> {
        validateSession()
            .catch { (error) -> AnyPublisher<Void, Error> in
                guard
                    let username = Current.defaults.string(forKey: "username"),
                    let password = try? Current.keychain.getString(username)
                else {
                    return Fail(error: error) 
                        .eraseToAnyPublisher()
                }

                return self.signIn(username: username, password: password)
                    .map { _ in Void() }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    func signIn(username: String, password: String) {
        signIn(username: username, password: password)
            .sink(
                receiveCompletion: { _ in }, 
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    func signIn(username: String, password: String) -> AnyPublisher<AuthenticationState, Error> {
        try? Current.keychain.set(password, key: username)
        Current.defaults.set(username, forKey: "username")
        
        isProcessingAuthRequest = true
        return client.login(accountName: username, password: password)
            .receive(on: DispatchQueue.main)
            .handleEvents(
                receiveOutput: { authenticationState in 
                    self.authenticationState = authenticationState
                },
                receiveCompletion: { completion in
                    self.handleAuthenticationFlowCompletion(completion)
                    self.isProcessingAuthRequest = false
                }
            )
            .eraseToAnyPublisher()
    }
    
    func handleTwoFactorOption(_ option: TwoFactorOption, authOptions: AuthOptionsResponse, serviceKey: String, sessionID: String, scnt: String) {
        self.presentingSignInAlert = false
        self.secondFactorData = SecondFactorData(
            option: option,
            authOptions: authOptions,
            sessionData: AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        )
    }

    func requestSMS(to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber, authOptions: AuthOptionsResponse, sessionData: AppleSessionData) {        
        isProcessingAuthRequest = true
        client.requestSMSSecurityCode(to: trustedPhoneNumber, authOptions: authOptions, sessionData: sessionData)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.handleAuthenticationFlowCompletion(completion)
                    self.isProcessingAuthRequest = false
                }, 
                receiveValue: { authenticationState in 
                    self.authenticationState = authenticationState
                    if case let AuthenticationState.waitingForSecondFactor(option, authOptions, sessionData) = authenticationState {
                        self.handleTwoFactorOption(option, authOptions: authOptions, serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func choosePhoneNumberForSMS(authOptions: AuthOptionsResponse, sessionData: AppleSessionData) {
        secondFactorData = SecondFactorData(option: .smsPendingChoice, authOptions: authOptions, sessionData: sessionData)
    }
    
    func submitSecurityCode(_ code: SecurityCode, sessionData: AppleSessionData) {
        isProcessingAuthRequest = true
        client.submitSecurityCode(code, sessionData: sessionData)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.handleAuthenticationFlowCompletion(completion)
                    self.isProcessingAuthRequest = false
                },
                receiveValue: { authenticationState in
                    self.authenticationState = authenticationState
                }
            )
            .store(in: &cancellables)
    }
    
    private func handleAuthenticationFlowCompletion(_ completion: Subscribers.Completion<Error>) {
        switch completion {
        case let .failure(error):
            if case .invalidUsernameOrPassword = error as? AuthenticationError,
               let username = Current.defaults.string(forKey: "username") {
                // remove any keychain password if we fail to log with an invalid username or password so it doesn't try again.
                try? Current.keychain.remove(username)
            }

            // This error message is not user friendly... need to extract some meaningful data in the different cases
            self.authError = AlertContent(title: "Error signing in", message: error.legibleLocalizedDescription)
        case .finished:
            switch self.authenticationState {
            case .authenticated, .unauthenticated:
                self.presentingSignInAlert = false
                self.secondFactorData = nil
            case let .waitingForSecondFactor(option, authOptions, sessionData):
                self.handleTwoFactorOption(option, authOptions: authOptions, serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
            }
        }
    }
    
    func signOut() {
        let username = Current.defaults.string(forKey: "username")
        Current.defaults.removeObject(forKey: "username")
        if let username = username {
            try? Current.keychain.remove(username)
        }
        AppleAPI.Current.network.session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
        authenticationState = .unauthenticated
    }
    
    // MARK: -
    
    func install(id: Xcode.ID) {
        // TODO:
    }
    
    func uninstall(id: Xcode.ID) {
        // TODO:
    }
    
    func reveal(id: Xcode.ID) {
        // TODO: show error if not
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installedXcode.path.url])
    }

    func select(id: Xcode.ID) {
        // TODO:
    }
    
    // MARK: - Private
    
    private func updateAllXcodes(_ xcodes: [AvailableXcode]) {
        let installedXcodes = Current.files.installedXcodes(Path.root/"Applications")
        var allXcodeVersions = xcodes.map { $0.version }
        for installedXcode in installedXcodes {
            // If an installed version isn't listed online, add the installed version
            if !allXcodeVersions.contains(where: { version in
                version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version)
            }) {
                allXcodeVersions.append(installedXcode.version)
            }
            // If an installed version is the same as one that's listed online which doesn't have build metadata, replace it with the installed version with build metadata
            else if let index = allXcodeVersions.firstIndex(where: { version in
                version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version) &&
                version.buildMetadataIdentifiers.isEmpty
            }) {
                allXcodeVersions[index] = installedXcode.version
            }
        }

        allXcodes = allXcodeVersions
            .sorted(by: >)
            .map { xcodeVersion in
                let installedXcode = installedXcodes.first(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) })
                return Xcode(
                    version: xcodeVersion,
                    installState: installedXcodes.contains(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) }) ? .installed : .notInstalled,
                    selected: false, 
                    path: installedXcode?.path.string
                )
            }
    }
    

    // MARK: - Nested Types

    struct AlertContent: Identifiable {
        var title: String
        var message: String
        var id: String { title + message }
    }

    struct SecondFactorData {
        let option: TwoFactorOption
        let authOptions: AuthOptionsResponse
        let sessionData: AppleSessionData
    }
}
