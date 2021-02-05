import AppKit
import AppleAPI
import Combine
import Path
import LegibleError
import KeychainAccess
import Path
import Version
import os.log

class AppState: ObservableObject {
    private let client = AppleAPI.Client()
    
    // MARK: - Published Properties
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var availableXcodes: [AvailableXcode] = [] {
        willSet {
            updateAllXcodes(
                availableXcodes: newValue, 
                installedXcodes: Current.files.installedXcodes(Path.root/"Applications"), 
                selectedXcodePath: selectedXcodePath
            )
        }
    }
    @Published var allXcodes: [Xcode] = []
    @Published var selectedXcodePath: String? {
        willSet {
            updateAllXcodes(
                availableXcodes: availableXcodes,
                installedXcodes: Current.files.installedXcodes(Path.root/"Applications"), 
                selectedXcodePath: newValue
            )
        }
    }
    @Published var updatePublisher: AnyCancellable?
    var isUpdating: Bool { updatePublisher != nil }
    @Published var presentingSignInAlert = false
    @Published var isProcessingAuthRequest = false
    @Published var secondFactorData: SecondFactorData?
    @Published var xcodeBeingConfirmedForUninstallation: Xcode?
    @Published var xcodeBeingConfirmedForInstallCancellation: Xcode?
    @Published var helperInstallState: HelperInstallState = .notInstalled
    /// Whether the user is being prepared for the helper installation alert with an explanation.
    /// This closure will be performed after the user chooses whether or not to proceed.
    @Published var isPreparingUserForActionRequiringHelper: ((Bool) -> Void)?

    // MARK: - Errors

    @Published var error: Error?
    @Published var authError: Error?
    
    // MARK: - Publisher Cancellables
    
    var cancellables = Set<AnyCancellable>()
    private var installationPublishers: [Version: AnyCancellable] = [:]
    private var selectPublisher: AnyCancellable?
    private var uninstallPublisher: AnyCancellable?
    
    // MARK: - 
    
    var dataSource: DataSource {
        Current.defaults.string(forKey: "dataSource").flatMap(DataSource.init(rawValue:)) ?? .default
    }
    
    // MARK: - Init
    
    init() {
        guard !isTesting else { return }
        try? loadCachedAvailableXcodes()
        checkIfHelperIsInstalled()
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
                Current.defaults.removeObject(forKey: "username")
            }

            Logger.appState.error("Authentication error: \(error.legibleDescription)")
            self.authError = error
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
    
    // MARK: - Helper
    
    /// Install the privileged helper if it isn't already installed.
    ///
    /// The way this is done is a little roundabout, because it requires user interaction in an alert before installation should be attempted.
    /// The first time this method is invoked should be with `shouldPrepareUserForHelperInstallation` set to true.
    /// If the helper is already installed, then nothing will happen.
    /// If the helper is not already installed, the user will be prepared for installation and this method will return early.
    /// If they consent to installing the helper then this method will be invoked again with  `shouldPrepareUserForHelperInstallation` set to false.
    /// This will install the helper.
    ///
    /// - Parameter shouldPrepareUserForHelperInstallation: Whether the user should be presented with an alert preparing them for helper installation.
    func installHelperIfNecessary(shouldPrepareUserForHelperInstallation: Bool = true) {
        guard helperInstallState == .installed || shouldPrepareUserForHelperInstallation == false else {
            isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                guard userConsented else { return }
                self.installHelperIfNecessary(shouldPrepareUserForHelperInstallation: false) 
            }
            return
        }
        
        installHelperIfNecessary()
            .sink(
                receiveCompletion: { [unowned self] completion in
                    if case let .failure(error) = completion {
                        self.error = error
                    }
                }, 
                receiveValue: {}
            )
            .store(in: &cancellables)
    }
    
    func installHelperIfNecessary() -> AnyPublisher<Void, Error> {
        Result {
            if helperInstallState == .notInstalled {
                try Current.helper.install()
                checkIfHelperIsInstalled()
            }
        }
        .publisher
        .subscribe(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    private func checkIfHelperIsInstalled() {
        helperInstallState = .unknown

        Current.helper.checkIfLatestHelperIsInstalled()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveValue: { installed in
                    self.helperInstallState = installed ? .installed : .notInstalled
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Install
    
    func install(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.version == id }) else { return }
        installationPublishers[id] = signInIfNeeded()
            .flatMap { [unowned self] in
                // signInIfNeeded might finish before the user actually authenticates if UI is involved. 
                // This publisher will wait for the @Published authentication state to change to authenticated or unauthenticated before finishing,
                // indicating that the user finished what they were doing in the UI.
                self.$authenticationState
                    .filter { state in
                        switch state {
                        case .authenticated, .unauthenticated: return true
                        case .waitingForSecondFactor: return false
                        }
                    }
                    .prefix(1)
                    .tryMap { state in
                        if state == .unauthenticated {
                            throw AuthenticationError.invalidSession
                        }
                        return Void()
                    }
            }
            .flatMap {
                // This request would've already been made if the Apple data source were being used.
                // That's not the case for the Xcode Releases data source.
                // We need the cookies from its response in order to download Xcodes though,
                // so perform it here first just to be sure.
                Current.network.dataTask(with: URLRequest.downloads)
                    .receive(on: DispatchQueue.main)
                    .map { _ in Void() }
                    .mapError { $0 as Error }
            }
            .flatMap { [unowned self] in
                self.install(.version(availableXcode), downloader: .aria2)
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [unowned self] completion in 
                    self.installationPublishers[id] = nil
                    if case let .failure(error) = completion {
                        self.error = error
                        if let index = self.allXcodes.firstIndex(where: { $0.id == id }) { 
                            self.allXcodes[index].installState = .notInstalled
                        }
                    }
                },
                receiveValue: { _ in }
            )
    }
    
    func cancelInstall(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.version == id }) else { return }

        // Cancel the publisher
        installationPublishers[id] = nil
                
        // If the download is cancelled by the user, clean up the download files that aria2 creates.
        // This isn't done as part of the publisher with handleEvents(receiveCancel:) because it shouldn't happen when e.g. the app quits.
        let expectedArchivePath = Path.xcodesApplicationSupport/"Xcode-\(availableXcode.version).\(availableXcode.filename.suffix(fromLast: "."))"
        let aria2DownloadMetadataPath = expectedArchivePath.parent/(expectedArchivePath.basename() + ".aria2")
        try? Current.files.removeItem(at: expectedArchivePath.url)
        try? Current.files.removeItem(at: aria2DownloadMetadataPath.url)
        
        if let index = allXcodes.firstIndex(where: { $0.id == id }) { 
            allXcodes[index].installState = .notInstalled
        }
    }
    
    // MARK: - Uninstall
    func uninstall(id: Xcode.ID) {
        guard
            let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version == id }),
            uninstallPublisher == nil
        else { return }
        
        uninstallPublisher = uninstallXcode(path: installedXcode.path)
            .flatMap { [unowned self] _ in
                self.updateSelectedXcodePath()
            }
            .sink(
                receiveCompletion: { [unowned self] completion in
                    if case let .failure(error) = completion {
                        self.error = error
                    }
                    self.uninstallPublisher = nil
                },
                receiveValue: { _ in }
        )
    }
    
    func reveal(id: Xcode.ID) {
        // TODO: show error if not
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installedXcode.path.url])
    }

    /// Make an Xcode active, a.k.a select it, in the `xcode-select` sense.
    ///
    /// The underlying work is done by the privileged helper, so we need to make sure that it's installed first.
    /// The way this is done is a little roundabout, because it requires user interaction in an alert before the `selectPublisher` is subscribed to.
    /// The first time this method is invoked should be with `shouldPrepareUserForHelperInstallation` set to true.
    /// If the helper is already installed, the Xcode will be made active immediately.
    /// If the helper is not already installed, the user will be prepared for installation and this method will return early.
    /// If they consent to installing the helper then this method will be invoked again with  `shouldPrepareUserForHelperInstallation` set to false.
    /// This will install the helper and make the Xcode active.
    ///
    /// - Parameter id: The identifier of the Xcode to make active.
    /// - Parameter shouldPrepareUserForHelperInstallation: Whether the user should be presented with an alert preparing them for helper installation before making the Xcode version active.
    func select(id: Xcode.ID, shouldPrepareUserForHelperInstallation: Bool = true) {
        guard helperInstallState == .installed || shouldPrepareUserForHelperInstallation == false else {
            isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                guard userConsented else { return }
                self.select(id: id, shouldPrepareUserForHelperInstallation: false) 
            }
            return
        }

        guard 
            let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version == id }),
            selectPublisher == nil
        else { return }
        
        selectPublisher = installHelperIfNecessary()
            .flatMap {
                Current.helper.switchXcodePath(installedXcode.path.string)
            }
            .flatMap { [unowned self] _ in
                self.updateSelectedXcodePath()
            }
            .sink(
                receiveCompletion: { [unowned self] completion in
                    if case let .failure(error) = completion {
                        self.error = error
                    }
                    self.selectPublisher = nil
                },
                receiveValue: { _ in }
            )
    }
    
    func open(id: Xcode.ID) {
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version == id }) else { return }
        NSWorkspace.shared.openApplication(at: installedXcode.path.url, configuration: .init())
    }
    
    func copyPath(id: Xcode.ID) {
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version == id }) else { return }
        NSPasteboard.general.declareTypes([.URL, .string], owner: nil)
        NSPasteboard.general.writeObjects([installedXcode.path.url as NSURL])
        NSPasteboard.general.setString(installedXcode.path.string, forType: .string)
    }

    func updateAllXcodes(availableXcodes: [AvailableXcode], installedXcodes: [InstalledXcode], selectedXcodePath: String?) {
        var adjustedAvailableXcodes = filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers(availableXcodes)
        
        // First, adjust all of the available Xcodes so that available and installed versions line up and the second part of this function works properly.
        if dataSource == .apple {
            for installedXcode in installedXcodes {
                // We can trust that build metadata identifiers are unique for each version of Xcode, so if we have it then it's all we need.
                // If build metadata matches exactly, replace the available version with the installed version.
                // This should handle Apple versions from /downloads/more which don't have build metadata identifiers. 
                if let index = adjustedAvailableXcodes.map(\.version).firstIndex(where: { $0.buildMetadataIdentifiers == installedXcode.version.buildMetadataIdentifiers }) {
                    adjustedAvailableXcodes[index].version = installedXcode.version
                }
                // If an installed version is the same as one that's listed online which doesn't have build metadata, replace it with the installed version
                // Not all prerelease Apple versions available online include build metadata
                else if let index = adjustedAvailableXcodes.firstIndex(where: { availableXcode in
                    availableXcode.version.isEquivalent(to: installedXcode.version) &&
                        availableXcode.version.buildMetadataIdentifiers.isEmpty
                }) {
                    adjustedAvailableXcodes[index].version = installedXcode.version
                }
            }
        }

        // Map all of the available versions into Xcode values that join available and installed Xcode data for display.
        var newAllXcodes = adjustedAvailableXcodes
            .map { availableXcode -> Xcode in
                let installedXcode = installedXcodes.first(where: { installedXcode in
                    availableXcode.version.isEquivalent(to: installedXcode.version) 
                })
                
                // If the existing install state is "installing", keep it 
                let existingXcodeInstallState = allXcodes.first { $0.version == availableXcode.version && $0.installState.installing }?.installState
                // Otherwise, determine it from whether there's an installed Xcode
                let defaultXcodeInstallState: XcodeInstallState = installedXcode.map { .installed($0.path) } ?? .notInstalled
                
                return Xcode(
                    version: availableXcode.version,
                    identicalBuilds: [],
                    installState: existingXcodeInstallState ?? defaultXcodeInstallState,
                    selected: installedXcode != nil && selectedXcodePath?.hasPrefix(installedXcode!.path.string) == true, 
                    icon: (installedXcode?.path.string).map(NSWorkspace.shared.icon(forFile:)),
                    requiredMacOSVersion: availableXcode.requiredMacOSVersion,
                    releaseNotesURL: availableXcode.releaseNotesURL,
                    sdks: availableXcode.sdks,
                    compilers: availableXcode.compilers,
                    downloadFileSize: availableXcode.fileSize
                )
            }
        
        // If an installed version isn't listed in the available versions, add the installed version
        // Xcode Releases should have all versions
        // Apple didn't used to keep all prerelease versions around but has started to recently
        for installedXcode in installedXcodes {
            if !newAllXcodes.contains(where: { xcode in xcode.version.isEquivalent(to: installedXcode.version) }) {
                newAllXcodes.append(
                    Xcode(
                        version: installedXcode.version, 
                        installState: .installed(installedXcode.path), 
                        selected: selectedXcodePath?.hasPrefix(installedXcode.path.string) == true, 
                        icon: NSWorkspace.shared.icon(forFile: installedXcode.path.string)
                    )
                )
            }
        }
        
        self.allXcodes = newAllXcodes.sorted { $0.version > $1.version }
    }
    
    /// Xcode Releases may have multiple releases with the same build metadata when a build doesn't change between candidate and final releases.
    /// For example, 12.3 RC and 12.3 are both build 12C33
    /// We don't care about that difference, so only keep the final release (GM or Release, in XCModel terms).
    /// The downside of this is that a user could technically have both releases installed, and so they won't both be shown in the list, but I think most users wouldn't do this.
    func filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers(_ availableXcodes: [AvailableXcode]) -> [AvailableXcode] {
        var filteredAvailableXcodes: [AvailableXcode] = []
        for availableXcode in availableXcodes {
            if availableXcode.version.buildMetadataIdentifiers.isEmpty {
                filteredAvailableXcodes.append(availableXcode)
                continue
            }
            
            let availableXcodesWithSameBuildMetadataIdentifiers = availableXcodes
                .filter({ $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers })
            if availableXcodesWithSameBuildMetadataIdentifiers.count > 1,
               availableXcode.version.prereleaseIdentifiers.isEmpty || availableXcode.version.prereleaseIdentifiers == ["GM"] {
                filteredAvailableXcodes.append(availableXcode)
            } else if availableXcodesWithSameBuildMetadataIdentifiers.count == 1 {
                filteredAvailableXcodes.append(availableXcode)
            }
        }
        return filteredAvailableXcodes
    } 
    
    // MARK: - Private
    
    private func uninstallXcode(path: Path) -> AnyPublisher<Void, Error> {
        return Deferred {
            Future { promise in
                do {
                    try Current.files.trashItem(at: path.url)
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
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
