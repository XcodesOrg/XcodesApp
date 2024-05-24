import AppKit
import AppleAPI
import Combine
import Path
import LegibleError
import KeychainAccess
import Path
import Version
import os.log
import DockProgress
import XcodesKit

class AppState: ObservableObject {
    private let client = AppleAPI.Client()
    internal let runtimeService = RuntimeService()
   
    // MARK: - Published Properties
    
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var availableXcodes: [AvailableXcode] = [] {
        willSet {
            if newValue.count > availableXcodes.count && availableXcodes.count != 0 {
                Current.notificationManager.scheduleNotification(title: localizeString("Notification.NewXcodeVersion.Title"), body: localizeString("Notification.NewXcodeVersion.Body"), category: .normal)
            }
            updateAllXcodes(
                availableXcodes: newValue, 
                installedXcodes: Current.files.installedXcodes(Path.installDirectory), 
                selectedXcodePath: selectedXcodePath
            )
        }
        didSet {
            autoInstallIfNeeded()
        }
    }
    @Published var allXcodes: [Xcode] = []
    @Published var selectedXcodePath: String? {
        willSet {
            updateAllXcodes(
                availableXcodes: availableXcodes,
                installedXcodes: Current.files.installedXcodes(Path.installDirectory),
                selectedXcodePath: newValue
            )
        }
    }
    @Published var updatePublisher: AnyCancellable?
    var isUpdating: Bool { updatePublisher != nil }
    @Published var presentedSheet: XcodesSheet? = nil
    @Published var isProcessingAuthRequest = false
    @Published var xcodeBeingConfirmedForUninstallation: Xcode?
    @Published var presentedAlert: XcodesAlert?
    @Published var presentedPreferenceAlert: XcodesPreferencesAlert?
    @Published var helperInstallState: HelperInstallState = .notInstalled
    /// Whether the user is being prepared for the helper installation alert with an explanation.
    /// This closure will be performed after the user chooses whether or not to proceed.
    @Published var isPreparingUserForActionRequiringHelper: ((Bool) -> Void)?

    // MARK: - Errors

    @Published var error: Error?
    @Published var authError: Error?
    
    // MARK: Advanced Preferences
    @Published var localPath = "" {
        didSet {
            Current.defaults.set(localPath, forKey: "localPath")
        }
    }
    
    @Published var installPath = "" {
        didSet {
            Current.defaults.set(installPath, forKey: "installPath")
        }
    }
    
    @Published var unxipExperiment = false {
        didSet {
            Current.defaults.set(unxipExperiment, forKey: "unxipExperiment")
        }
    }
    
    @Published var createSymLinkOnSelect = false {
        didSet {
            Current.defaults.set(createSymLinkOnSelect, forKey: "createSymLinkOnSelect")
        }
    }
    
    var createSymLinkOnSelectDisabled: Bool {
        return onSelectActionType == .rename
    }
    
    @Published var onSelectActionType = SelectedActionType.none {
        didSet {
            Current.defaults.set(onSelectActionType.rawValue, forKey: "onSelectActionType")
            
            if onSelectActionType == .rename {
                createSymLinkOnSelect = false
            }
        }
    }
    
    @Published var showOpenInRosettaOption = false {
        didSet {
            Current.defaults.set(showOpenInRosettaOption, forKey: "showOpenInRosettaOption")
        }
    }
    
    // MARK: - Runtimes
    
    @Published var downloadableRuntimes: [DownloadableRuntime] = []
    @Published var installedRuntimes: [CoreSimulatorImage] = []

    // MARK: - Publisher Cancellables
    
    var cancellables = Set<AnyCancellable>()
    private var installationPublishers: [Version: AnyCancellable] = [:]
    internal var runtimePublishers: [String: Task<(), any Error>] = [:]
    private var selectPublisher: AnyCancellable?
    private var uninstallPublisher: AnyCancellable?
    private var autoInstallTimer: Timer?
    
    // MARK: - Dock Progress Tracking
    
    public static let totalProgressUnits = Int64(10)
    public static let unxipProgressWeight = Int64(1)
    var overallProgress = Progress()
    var unxipProgress = {
        let progress = Progress(totalUnitCount: totalProgressUnits)
        progress.kind = .file
        progress.fileOperationKind = .copying
        return progress
    }()
    
    // MARK: - 
    
    var dataSource: DataSource {
        Current.defaults.string(forKey: "dataSource").flatMap(DataSource.init(rawValue:)) ?? .default
    }

    var savedUsername: String? {
        Current.defaults.string(forKey: "username")
    }

    var hasSavedUsername: Bool {
        savedUsername != nil
    }
    
    var bottomStatusBarMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let finishDate = formatter.date(from: "11/06/2022")
        
        if Date().compare(finishDate!) == .orderedAscending {
            return String(format: localizeString("WWDC.Message"), "2022")
        }
        return ""
    }
    
    // MARK: - Init
    
    init() {
        guard !isTesting else { return }
        try? loadCachedAvailableXcodes()
        try? loadCacheDownloadableRuntimes()
        checkIfHelperIsInstalled()
        setupAutoInstallTimer()
        setupDefaults()
    }
    
    func setupDefaults() {
        localPath = Current.defaults.string(forKey: "localPath") ?? Path.defaultXcodesApplicationSupport.string
        unxipExperiment = Current.defaults.bool(forKey: "unxipExperiment") ?? false
        createSymLinkOnSelect = Current.defaults.bool(forKey: "createSymLinkOnSelect") ?? false
        onSelectActionType = SelectedActionType(rawValue: Current.defaults.string(forKey: "onSelectActionType") ?? "none") ?? .none
        installPath = Current.defaults.string(forKey: "installPath") ?? Path.defaultInstallDirectory.string
        showOpenInRosettaOption = Current.defaults.bool(forKey: "showOpenInRosettaOption") ?? false
    }
    
    // MARK: Timer
    /// Runs a timer every 6 hours when app is open to check if it needs to auto install any xcodes
    func setupAutoInstallTimer() {
        guard let storageValue = UserDefaults.standard.object(forKey: "autoInstallation") as? Int, let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }
        
        if autoInstallType == .none { return }
        
        autoInstallTimer = Timer.scheduledTimer(withTimeInterval: 60*60*6, repeats: true) { [weak self] _ in
            self?.updateIfNeeded()
        }
    }
    // MARK: - Authentication
    
    func validateADCSession(path: String) -> AnyPublisher<Void, Error> {
        return Current.network.dataTask(with: URLRequest.downloadADCAuth(path: path))
            .receive(on: DispatchQueue.main)
            .tryMap { result -> Void in
                let httpResponse = result.response as! HTTPURLResponse
                if httpResponse.statusCode == 401 {
                    throw AuthenticationError.notAuthorized
                }
            }
            .eraseToAnyPublisher()
    }
    
    func validateADCSession(path: String) async throws {
        let result = try await Current.network.dataTaskAsync(with: URLRequest.downloadADCAuth(path: path))
        let httpResponse = result.1 as! HTTPURLResponse
        if httpResponse.statusCode == 401 {
            throw AuthenticationError.notAuthorized
        }
    }
    
    func validateSession() -> AnyPublisher<Void, Error> {
        
        return Current.network.validateSession()
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveCompletion: { completion in 
                if case .failure = completion {
                    // this is causing some awkwardness with showing an alert with the error and also popping up the sign in view
                    // self.authenticationState = .unauthenticated
                    // self.presentedSheet = .signIn
                }
            })
            .eraseToAnyPublisher()
    }
    
    func signInIfNeeded() -> AnyPublisher<Void, Error> {
        validateSession()
            .catch { (error) -> AnyPublisher<Void, Error> in
                guard
                    let username = self.savedUsername,
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
        authError = nil
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
        self.presentedSheet = .twoFactor(.init(
            option: option,
            authOptions: authOptions,
            sessionData: AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        ))
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
        self.presentedSheet = .twoFactor(.init(
            option: .smsPendingChoice,
            authOptions: authOptions,
            sessionData: sessionData
        ))
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
            // remove saved username and any stored keychain password if authentication fails so it doesn't try again.
            clearLoginCredentials()
            Logger.appState.error("Authentication error: \(error.legibleDescription)")
            self.authError = error
        case .finished:
            switch self.authenticationState {
                case .authenticated, .unauthenticated, .notAppleDeveloper:
                self.presentedSheet = nil
            case let .waitingForSecondFactor(option, authOptions, sessionData):
                self.handleTwoFactorOption(option, authOptions: authOptions, serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
            }
        }
    }
    
    func signOut() {
        clearLoginCredentials()
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
            presentedAlert = .privilegedHelper
            return
        }
        
        installHelperIfNecessary()
            .sink(
                receiveCompletion: { [unowned self] completion in
                    if case let .failure(error) = completion {
                        self.error = error
                        self.presentedAlert = .generic(title: localizeString("Alert.PrivilegedHelper.Error.Title"), message: error.legibleLocalizedDescription)
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
    
    func checkMinVersionAndInstall(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.version == id }) else { return }
        
        // Check to see if users macOS is supported
        if let requiredMacOSVersion = availableXcode.requiredMacOSVersion {
            if hasMinSupportedOS(requiredMacOSVersion: requiredMacOSVersion) {
                // prompt
                self.presentedAlert = .checkMinSupportedVersion(xcode: availableXcode, macOS: ProcessInfo.processInfo.operatingSystemVersion.versionString())
                return
            }
        }
        
        switch self.dataSource {
        case .apple:
            install(id: id)
        case .xcodeReleases:
            install(id: id)
        }
    }
    
    func hasMinSupportedOS(requiredMacOSVersion: String) -> Bool {
        let split = requiredMacOSVersion.components(separatedBy: ".").compactMap { Int($0) }
        let xcodeMinimumMacOSVersion = OperatingSystemVersion(majorVersion: split[safe: 0] ?? 0, minorVersion: split[safe: 1] ?? 0, patchVersion: split[safe: 2] ?? 0)
        
        return !ProcessInfo.processInfo.isOperatingSystemAtLeast(xcodeMinimumMacOSVersion)
    }
    
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
                            case .authenticated, .unauthenticated, .notAppleDeveloper: return true
                        case .waitingForSecondFactor: return false
                        }
                    }
                    .prefix(1)
                    .tryMap { state in
                        if state == .unauthenticated {
                            throw AuthenticationError.invalidSession
                        }
                        if state == .notAppleDeveloper {
                            throw AuthenticationError.notDeveloperAppleId
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
                    .map(\.data)
                    .decode(type: Downloads.self, decoder: configure(JSONDecoder()) {
                        $0.dateDecodingStrategy = .formatted(.downloadsDateModified)
                    })
                    .tryMap { downloads -> Void in
                        if downloads.hasError {
                            throw AuthenticationError.invalidResult(resultString: downloads.resultsString)
                        }
                       if downloads.downloads == nil {
                            throw AuthenticationError.invalidResult(resultString: localizeString("DownloadingError"))
                        }
                    }
                    .mapError { $0 as Error }
            }
            .flatMap { [unowned self] in
                self.install(.version(availableXcode), downloader: Downloader(rawValue: UserDefaults.standard.string(forKey: "downloader") ?? "aria2") ?? .aria2)
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [unowned self] completion in 
                    self.installationPublishers[id] = nil
                    if case let .failure(error) = completion {
                        // Prevent setting the app state error if it is an invalid session, we will present the sign in view instead
                        if error as? AuthenticationError != .invalidSession {
                            self.error = error
                            self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                        }
                        if let index = self.allXcodes.firstIndex(where: { $0.id == id }) { 
                            self.allXcodes[index].installState = .notInstalled
                        }
                    }
                },
                receiveValue: { _ in }
            )
    }
    
    /// Skips using the username/password to log in to Apple, and simply gets a Auth Cookie used in downloading
    /// As of Nov 2022 this was returning a 403 forbidden
    func installWithoutLogin(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.version == id }) else { return }
        
        installationPublishers[id] = self.install(.version(availableXcode), downloader: Downloader(rawValue: UserDefaults.standard.string(forKey: "downloader") ?? "aria2") ?? .aria2)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [unowned self] completion in
                    self.installationPublishers[id] = nil
                    if case let .failure(error) = completion {
                        // Prevent setting the app state error if it is an invalid session, we will present the sign in view instead
                        if error as? AuthenticationError != .invalidSession {
                            self.error = error
                            self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                        }
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
        
        resetDockProgressTracking()
                
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
    func uninstall(xcode: Xcode) {
        guard
            let installedXcodePath = xcode.installedPath,
            uninstallPublisher == nil
        else { return }
        
        uninstallPublisher = uninstallXcode(path: installedXcodePath)
            .flatMap { [unowned self] _ in
                self.updateSelectedXcodePath()
            }
            .sink(
                receiveCompletion: { [unowned self] completion in
                    if case let .failure(error) = completion {
                        self.error = error
                        self.presentedAlert = .generic(title: localizeString("Alert.Uninstall.Error.Title"), message: error.legibleLocalizedDescription)
                    }
                    self.uninstallPublisher = nil
                },
                receiveValue: { _ in }
        )
    }
    
    func reveal(_ path: Path?) {
        // TODO: show error if not
        guard let path = path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([path.url])
    }
    
    func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
    /// - Parameter xcode: The Xcode to make active.
    /// - Parameter shouldPrepareUserForHelperInstallation: Whether the user should be presented with an alert preparing them for helper installation before making the Xcode version active.
    func select(xcode: Xcode, shouldPrepareUserForHelperInstallation: Bool = true) {
        guard helperInstallState == .installed || shouldPrepareUserForHelperInstallation == false else {
            isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                guard userConsented else { return }
                self.select(xcode: xcode, shouldPrepareUserForHelperInstallation: false)
            }
            presentedAlert = .privilegedHelper
            return
        }

        guard
            var installedXcodePath = xcode.installedPath,
            selectPublisher == nil
        else { return }
       
        if onSelectActionType == .rename {
            guard let newDestinationXcodePath = renameToXcode(xcode: xcode) else { return }
            installedXcodePath = newDestinationXcodePath
        }
        
        selectPublisher = installHelperIfNecessary()
            .flatMap {
                Current.helper.switchXcodePath(installedXcodePath.string)
            }
            .flatMap { [unowned self] _ in
                self.updateSelectedXcodePath()
            }
            .sink(
                receiveCompletion: { [unowned self] completion in
                    if case let .failure(error) = completion {
                        self.error = error
                        self.presentedAlert = .generic(title: localizeString("Alert.Select.Error.Title"), message: error.legibleLocalizedDescription)
                    } else {
                        if self.createSymLinkOnSelect {
                            createSymbolicLink(xcode: xcode)
                        }
                    }
                    self.selectPublisher = nil
                },
                receiveValue: { _ in }
            )
    }
    
    func open(xcode: Xcode, openInRosetta: Bool? = false) {
        switch xcode.installState {
        case let .installed(path):
            let config = NSWorkspace.OpenConfiguration.init()
            if (openInRosetta ?? false) {
                config.architecture = CPU_TYPE_X86_64
            }
            config.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.openApplication(at: path.url, configuration: config)
        default:
            Logger.appState.error("\(xcode.id) is not installed")
            return
        }
    }
    
    func copyPath(xcode: Xcode) {
        guard let installedXcodePath = xcode.installedPath else { return }
        
        NSPasteboard.general.declareTypes([.URL, .string], owner: nil)
        NSPasteboard.general.writeObjects([installedXcodePath.url as NSURL])
        NSPasteboard.general.setString(installedXcodePath.string, forType: .string)
    }

    func copyReleaseNote(from url: URL?) {
      guard let url = url else { return }
      NSPasteboard.general.declareTypes([.URL, .string], owner: nil)
      NSPasteboard.general.writeObjects([url as NSURL])
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    
    func createSymbolicLink(xcode: Xcode, isBeta: Bool = false) {
        guard let installedXcodePath = xcode.installedPath else { return }
        
        let destinationPath: Path = Path.installDirectory/"Xcode\(isBeta ? "-Beta" : "").app"
        
        // does an Xcode.app file exist?
        if FileManager.default.fileExists(atPath: destinationPath.string) {
            do {
                // if it's not a symlink, error because we don't want to delete an actual xcode.app file
                let attributes: [FileAttributeKey : Any]? = try? FileManager.default.attributesOfItem(atPath: destinationPath.string)
                
                if attributes?[.type] as? FileAttributeType == FileAttributeType.typeSymbolicLink {
                    try FileManager.default.removeItem(atPath: destinationPath.string)
                    Logger.appState.info("Successfully deleted old symlink")
                } else {
                    self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: localizeString("Alert.SymLink.Message"))
                    return
                }
            } catch {
                self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: error.localizedDescription)
            }
        }
        
        do {
            try FileManager.default.createSymbolicLink(atPath: destinationPath.string, withDestinationPath: installedXcodePath.string)
            Logger.appState.info("Successfully created symbolic link with Xcode\(isBeta ? "-Beta": "").app")
        } catch {
            Logger.appState.error("Unable to create symbolic Link")
            self.error = error
            self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: error.legibleLocalizedDescription)
        }
    }
    
    func renameToXcode(xcode: Xcode) -> Path? {
        guard let installedXcodePath = xcode.installedPath else { return nil }
        
        let destinationPath: Path = Path.installDirectory/"Xcode.app"
        
        // rename any old named `Xcode.app` to the Xcodes versioned named files
        if FileManager.default.fileExists(atPath: destinationPath.string) {
            if let originalXcode = Current.files.installedXcode(destination: destinationPath) {
                let newName = "Xcode-\(originalXcode.version.descriptionWithoutBuildMetadata).app"
                Logger.appState.debug("Found Xcode.app - renaming back to \(newName)")
                do {
                    try destinationPath.rename(to: newName)
                } catch {
                    Logger.appState.error("Unable to create rename Xcode.app back to original")
                    self.error = error
                    // TODO UPDATE MY ERROR STRING
                    self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: error.legibleLocalizedDescription)
                }
            }
        }
        // rename passed in xcode to xcode.app
        Logger.appState.debug("Found Xcode.app - renaming back to Xcode.app")
        do {
            return try installedXcodePath.rename(to: "Xcode.app")
        } catch {
            Logger.appState.error("Unable to create rename Xcode.app back to original")
            self.error = error
            // TODO UPDATE MY ERROR STRING
            self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: error.legibleLocalizedDescription)
        }
        return nil
    }

    func updateAllXcodes(availableXcodes: [AvailableXcode], installedXcodes: [InstalledXcode], selectedXcodePath: String?) {
        var adjustedAvailableXcodes = availableXcodes
        
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
            .filter { availableXcode in
                // If we don't have the build identifier, don't attempt to filter prerelease versions with identical build identifiers
                guard !availableXcode.version.buildMetadataIdentifiers.isEmpty else { return true }

                let availableXcodesWithIdenticalBuildIdentifiers = availableXcodes
                    .filter({ $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers })
                
                // Include this version if there's only one with this build identifier
                return availableXcodesWithIdenticalBuildIdentifiers.count == 1 ||
                    // Or if there's more than one with this build identifier and this is the release version
                    availableXcodesWithIdenticalBuildIdentifiers.count > 1 && availableXcode.version.prereleaseIdentifiers.isEmpty
            }            
            .map { availableXcode -> Xcode in
                let installedXcode = installedXcodes.first(where: { installedXcode in
                    availableXcode.version.isEquivalent(to: installedXcode.version) 
                })

                let identicalBuilds: [Version]
                let prereleaseAvailableXcodesWithIdenticalBuildIdentifiers = availableXcodes
                    .filter {
                        return $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers &&
                            !$0.version.prereleaseIdentifiers.isEmpty &&
                            // If we don't have the build identifier, don't consider this as a potential identical build
                            !$0.version.buildMetadataIdentifiers.isEmpty
                    }
                // If this is the release version, add the identical builds to it
                if !prereleaseAvailableXcodesWithIdenticalBuildIdentifiers.isEmpty, availableXcode.version.prereleaseIdentifiers.isEmpty {
                    identicalBuilds = [availableXcode.version] + prereleaseAvailableXcodesWithIdenticalBuildIdentifiers.map(\.version)
                } else {
                    identicalBuilds = []
                }
                
                // If the existing install state is "installing", keep it 
                let existingXcodeInstallState = allXcodes.first { $0.version == availableXcode.version && $0.installState.installing }?.installState
                // Otherwise, determine it from whether there's an installed Xcode
                let defaultXcodeInstallState: XcodeInstallState = installedXcode.map { .installed($0.path) } ?? .notInstalled
                
                return Xcode(
                    version: availableXcode.version,
                    identicalBuilds: identicalBuilds,
                    installState: existingXcodeInstallState ?? defaultXcodeInstallState,
                    selected: installedXcode != nil && selectedXcodePath?.hasPrefix(installedXcode!.path.string) == true, 
                    icon: (installedXcode?.path.string).map(NSWorkspace.shared.icon(forFile:)),
                    requiredMacOSVersion: availableXcode.requiredMacOSVersion,
                    releaseNotesURL: availableXcode.releaseNotesURL,
                    releaseDate: availableXcode.releaseDate,
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

    /// removes saved username and credentials stored in keychain
    private func clearLoginCredentials() {
        if let username = savedUsername {
            try? Current.keychain.remove(username)
        }
        Current.defaults.removeObject(forKey: "username")

    }

    // MARK: - Nested Types

    struct AlertContent: Identifiable {
        var title: String
        var message: String
        var id: String { title + message }
    }
}

extension OperatingSystemVersion {
    func versionString() -> String {
        return String(majorVersion) + "." + String(minorVersion) + "." + String(patchVersion)
    }
}
