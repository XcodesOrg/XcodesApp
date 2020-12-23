import AppKit
import AppleAPI
import Combine
import Path
import PromiseKit
import LegibleError

class AppState: ObservableObject {
    private let list = XcodeList()
    private let client = AppleAPI.Client()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var allVersions: [XcodeVersion] = []
    @Published var error: AlertContent?
    @Published var presentingSignInAlert = false
    @Published var secondFactorData: SecondFactorData?
    
    // MARK: - Authentication
    
    func validateSession() -> AnyPublisher<Void, Error> {
        return client.validateSession()
            .handleEvents(receiveCompletion: { completion in 
                if case .failure = completion {
                    self.authenticationState = .unauthenticated
                    self.presentingSignInAlert = true
                }
            })
            .eraseToAnyPublisher()
    }
    
    func login(username: String, password: String) {
        client.login(accountName: username, password: password)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.handleAuthenticationFlowCompletion(completion)
                }, 
                receiveValue: { authenticationState in 
                    self.authenticationState = authenticationState
                }
            )
            .store(in: &cancellables)
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
        client.requestSMSSecurityCode(to: trustedPhoneNumber, authOptions: authOptions, sessionData: sessionData)
            .sink(
                receiveCompletion: { completion in
                    self.handleAuthenticationFlowCompletion(completion)
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
        client.submitSecurityCode(code, sessionData: sessionData)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.handleAuthenticationFlowCompletion(completion)
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
            self.error = AlertContent(title: "Error signing in", message: error.legibleLocalizedDescription)
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
    
    // MARK: - Load Xcode Versions
    
    func update() {
        // Treat this implementation as a placeholder that can be thrown away.
        // It's only here to make it easy to see that auth works.
        update()
            .sink(receiveCompletion: { _ in },
                  receiveValue: { _ in })
            .store(in: &cancellables)     
    }
    
    public func update() -> AnyPublisher<[Xcode], Error> {
        // Wrap the Promise API in a Publisher for now
        return Deferred {
            Future { promise in
                self.list.update()
                    .done { promise(.success($0)) }
                    .catch { promise(.failure($0)) }                
            }
        }
        .handleEvents(receiveOutput: { [unowned self] xcodes in
            self.updateAllVersions(xcodes)
        })
        .eraseToAnyPublisher()
    }
    
    private func updateAllVersions(_ xcodes: [Xcode]) {
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

        allVersions = allXcodeVersions
            .sorted(by: >)
            .map { xcodeVersion in
                let installedXcode = installedXcodes.first(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) })
                return XcodeVersion(
                    title: xcodeVersion.xcodeDescription, 
                    installState: installedXcodes.contains(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) }) ? .installed : .notInstalled,
                    selected: false, 
                    path: installedXcode?.path.string
                )
            }
    }
    
    func install(id: String) {
        // TODO:
    }
    
    func uninstall(id: String) {
        // TODO:
    }
    
    func reveal(id: String) {
        // TODO: show error if not
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version.xcodeDescription == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installedXcode.path.url])
    }

    func select(id: String) {
        // TODO:
    }

    // MARK: - Nested Types
    
    struct XcodeVersion: Identifiable {
        let title: String
        let installState: InstallState
        let selected: Bool
        let path: String?
        var id: String { title }
        var installed: Bool { installState == .installed }
    }

    enum InstallState: Equatable {
        case notInstalled
        case installing(Progress)
        case installed
    }

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
