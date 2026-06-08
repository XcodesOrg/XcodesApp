import AppKit
import XcodesLoginKit
import XcodesLoginKitSecurityKey
import Path
import LegibleError
import KeychainAccess
import Path
import Version
import os.log
import DockProgress
import XcodesKit

enum PreferenceKey: String {
    case installPath
    case localPath
    case unxipExperiment
    case createSymLinkOnSelect
    case onSelectActionType
    case showOpenInRosettaOption
    case autoInstallation
    case SUEnableAutomaticChecks
    case includePrereleaseVersions
    case downloader
    case dataSource
    case xcodeListCategory
    case allowedMajorVersions
    case hideSupportXcodes
    case xcodeListArchitectures
    case enableGroupedXcodeList
    case expandedMajorXcodeVersions
    case expandedMinorXcodeVersions

    func isManaged() -> Bool { UserDefaults.standard.objectIsForced(forKey: self.rawValue) }
}

@MainActor
class AppState: ObservableObject {
    private var client: XcodesLoginKit.Client { Current.network.loginClient }
    internal var runtimeService: RuntimeService

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
    @Published var updateTask: Task<Void, Never>?
    var updateTaskID: UUID?
    var isUpdating: Bool { updateTask != nil }
    @Published var presentedSheet: XcodesSheet? = nil
    @Published var isProcessingAuthRequest = false
    private var authenticationRequestID: UUID?
    private var authenticationTask: Task<Void, Never>?
    private var authenticationTaskID: UUID?
    @Published var xcodeBeingConfirmedForUninstallation: Xcode?
    @Published var presentedAlert: XcodesAlert?
    @Published var presentedPreferenceAlert: XcodesPreferencesAlert?
    @Published var helperInstallState: HelperInstallState = .notInstalled
    /// Whether the user is being prepared for the helper installation alert with an explanation.
    /// This closure will be performed after the user chooses whether or not to proceed.
    @Published var isPreparingUserForActionRequiringHelper: ((Bool) -> Void)?
    var helperActionPreparationID: UUID?

    // MARK: - Errors

    @Published var error: Error?
    @Published var authError: Error?

    // MARK: Advanced Preferences
    @Published var localPath = "" {
        didSet {
            Current.defaults.set(localPath, forKey: "localPath")
        }
    }

    var disableLocalPathChange: Bool { PreferenceKey.localPath.isManaged() }

    @Published var installPath = "" {
        didSet {
            Current.defaults.set(installPath, forKey: "installPath")
        }
    }

    var disableInstallPathChange: Bool { PreferenceKey.installPath.isManaged() }

    @Published var unxipExperiment = false {
        didSet {
            Current.defaults.set(unxipExperiment, forKey: "unxipExperiment")
        }
    }

    var disableUnxipExperiment: Bool { PreferenceKey.unxipExperiment.isManaged() }

    @Published var createSymLinkOnSelect = false {
        didSet {
            Current.defaults.set(createSymLinkOnSelect, forKey: "createSymLinkOnSelect")
        }
    }

    var createSymLinkOnSelectDisabled: Bool {
        return onSelectActionType == .rename || PreferenceKey.createSymLinkOnSelect.isManaged()
    }

    @Published var onSelectActionType = SelectedActionType.none {
        didSet {
            Current.defaults.set(onSelectActionType.rawValue, forKey: "onSelectActionType")

            if onSelectActionType == .rename {
                createSymLinkOnSelect = false
            }
        }
    }

    var onSelectActionTypeDisabled: Bool { PreferenceKey.onSelectActionType.isManaged() }

    @Published var showOpenInRosettaOption = false {
        didSet {
            Current.defaults.set(showOpenInRosettaOption, forKey: "showOpenInRosettaOption")
        }
    }

    @Published var terminateAfterLastWindowClosed = false {
        didSet {
            Current.defaults.set(terminateAfterLastWindowClosed, forKey: "terminateAfterLastWindowClosed")
        }
    }

    @Published var enableGroupedXcodeList = true {
        didSet {
            Current.defaults.set(enableGroupedXcodeList, forKey: PreferenceKey.enableGroupedXcodeList.rawValue)
        }
    }

    // MARK: - Runtimes

    @Published var downloadableRuntimes: [DownloadableRuntime] = []
    @Published var installedRuntimes: [CoreSimulatorImage] = []

    // MARK: - Operation State

    var downloadableRuntimesTask: Task<Void, Never>?
    var downloadableRuntimesTaskID: UUID?
    var installedRuntimesTask: Task<Void, Never>?
    var installedRuntimesTaskID: UUID?
    internal var installationTasks: [XcodeID: Task<Void, Never>] = [:]
    internal var installationTaskIDs: [XcodeID: UUID] = [:]
    internal var runtimeTasks: [String: Task<Void, Never>] = [:]
    internal var runtimeTaskIDs: [String: UUID] = [:]
    internal var deleteRuntimeTask: Task<Void, Never>?
    internal var deleteRuntimeTaskID: UUID?
    internal var helperInstallTask: Task<Void, Never>?
    internal var helperInstallTaskID: UUID?
    internal var postInstallTask: Task<Void, Never>?
    internal var postInstallTaskID: UUID?
    private var helperStatusTask: Task<Void, Never>?
    internal var selectTask: Task<Void, Never>?
    internal var selectTaskID: UUID?
    internal var uninstallTask: Task<Void, Never>?
    internal var uninstallTaskID: UUID?
    private var autoInstallTimer: Timer?

    // MARK: - Dock Progress Tracking

    public static let totalProgressUnits = Int64(10)
    public static let unxipProgressWeight = Int64(1)
    var overallProgress = Progress()
    var unxipProgress = AppState.makeUnxipProgress()
    var overallProgressChildIDs = Set<ObjectIdentifier>()

    static func makeUnxipProgress() -> Progress {
        let progress = Progress(totalUnitCount: totalProgressUnits)
        progress.kind = .file
        progress.fileOperationKind = .copying
        return progress
    }

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

    init(runtimeService: RuntimeService = RuntimeService()) {
        self.runtimeService = runtimeService
        guard !isTesting else { return }
        try? loadCachedAvailableXcodes()
        try? loadCacheDownloadableRuntimes()
        helperStatusTask = Task { @MainActor in
            await checkIfHelperIsInstalled()
            helperStatusTask = nil
        }
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
        terminateAfterLastWindowClosed = Current.defaults.bool(forKey: "terminateAfterLastWindowClosed") ?? false
        enableGroupedXcodeList = Current.defaults.get(forKey: PreferenceKey.enableGroupedXcodeList.rawValue) as? Bool ?? true
    }

    // MARK: Timer
    /// Runs a timer every 6 hours when app is open to check if it needs to auto install any xcodes
    func setupAutoInstallTimer() {
        guard let storageValue = Current.defaults.get(forKey: "autoInstallation") as? Int, let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }

        if autoInstallType == .none { return }

        autoInstallTimer = Timer.scheduledTimer(withTimeInterval: 60*60*6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateIfNeeded()
            }
        }
    }
    // MARK: - Authentication

    func validateADCSession(path: String) async throws {
        try await DeveloperPortalSessionService(
            loadData: { request in
                try await Current.network.dataTaskAsync(with: request)
            },
            unauthorizedError: { AuthenticationError.notAuthorized }
        ).validateADCSession(path: path)
    }

    func validateSessionAsync() async throws {
        try await Current.network.validateSessionAsync()
    }

    func signInIfNeededAsync() async throws {
        do {
            try await validateSessionAsync()
        } catch {
            guard
                let username = savedUsername,
                let password = try? Current.keychain.getString(username)
            else {
                throw error
            }

            _ = try await signInAsync(username: username, password: password)
        }
    }

    func signIn(username: String, password: String?) {
        authError = nil
        startAuthenticationTask {
            _ = try await self.signInAsync(username: username.lowercased(), password: password)
        }
    }

    func signInAsync(username: String, password: String?) async throws -> AuthenticationState {
        if let password, !password.isEmpty {
            try? Current.keychain.set(password, key: username)
        }
        Current.defaults.set(username, forKey: "username")

        return try await performAuthenticationRequest {
            try await client.authenticationState(accountName: username, password: password)
        }
    }

    func submitFederatedAuthenticationCallback(_ callbackURLString: String) {
        startAuthenticationTask {
            _ = try await self.performAuthenticationRequest {
                try await self.client.validateFederatedCallbackURLString(callbackURLString)
            }
        }
    }

    func handleTwoFactorOption(_ option: TwoFactorOption, authOptions: AuthOptionsResponse, serviceKey: String, sessionID: String, scnt: String) {
        let sessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)

        if option == .securityKey, fido2DeviceIsPresent() && !fido2DeviceNeedsPin() {
            createAndSubmitSecurityKeyAssertationWithPinCode(nil, sessionData: sessionData, authOptions: authOptions)
        } else {
            self.presentedSheet = .twoFactor(.init(
                option: option,
                authOptions: authOptions,
                sessionData: sessionData
            ))
        }
    }

    func requestSMS(to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber, authOptions: AuthOptionsResponse, sessionData: AppleSessionData) {
        startAuthenticationTask {
            _ = try await self.performAuthenticationRequest {
                try await self.client.requestSMSSecurityCode(to: trustedPhoneNumber, authOptions: authOptions, sessionData: sessionData)
            }
        }
    }

    func choosePhoneNumberForSMS(authOptions: AuthOptionsResponse, sessionData: AppleSessionData) {
        self.presentedSheet = .twoFactor(.init(
            option: .smsPendingChoice,
            authOptions: authOptions,
            sessionData: sessionData
        ))
    }

    func submitSecurityCode(_ code: SecurityCode, sessionData: AppleSessionData) {
        startAuthenticationTask {
            _ = try await self.performAuthenticationRequest {
                try await self.client.submitSecurityCode(code, sessionData: sessionData)
            }
        }
    }

    func createAndSubmitSecurityKeyAssertationWithPinCode(_ pinCode: String?, sessionData: AppleSessionData, authOptions: AuthOptionsResponse) {
        self.presentedSheet = .securityKeyTouchToConfirm

        startAuthenticationTask {
            _ = try await self.performAuthenticationRequest {
                try await self.client.submitSecurityKeyPinCode(pinCode, sessionData: sessionData, authOptions: authOptions)
            }
        }
    }

    func fido2DeviceIsPresent() -> Bool {
        client.hasSecurityKeyDeviceAttached()
    }

    func fido2DeviceNeedsPin() -> Bool {
        do {
            return try client.securityKeyDeviceNeedsPin()
        } catch {
            authError = error
            return true
        }
    }

    func cancelSecurityKeyAssertationRequest() {
        self.client.cancelSecurityKeyAssertationRequest()
    }

    private func handleAuthenticationFlowFailure(_ error: Error) {
        // remove saved username and any stored keychain password if authentication fails so it doesn't try again.
        clearLoginCredentials()
        Logger.appState.error("Authentication error: \(error.legibleDescription)")
        self.authError = error
    }

    private func handleAuthenticationFlowSuccess() {
        switch self.authenticationState {
        case .authenticated, .unauthenticated, .notAppleDeveloper:
            self.presentedSheet = nil
        case .waitingForFederatedAuthentication:
            break
        case let .waitingForSecondFactor(option, authOptions, sessionData):
            self.handleTwoFactorOption(option, authOptions: authOptions, serviceKey: sessionData.serviceKey, sessionID: sessionData.sessionID, scnt: sessionData.scnt)
        }
    }

    private func performAuthenticationRequest(
        _ operation: () async throws -> AuthenticationState
    ) async throws -> AuthenticationState {
        let requestID = UUID()
        authenticationRequestID = requestID
        isProcessingAuthRequest = true
        defer {
            if authenticationRequestID == requestID {
                isProcessingAuthRequest = false
                authenticationRequestID = nil
            }
        }

        do {
            let authenticationState = try await operation()
            guard authenticationRequestID == requestID else { return authenticationState }
            self.authenticationState = authenticationState
            handleAuthenticationFlowSuccess()
            return authenticationState
        } catch {
            if authenticationRequestID == requestID {
                handleAuthenticationFlowFailure(error)
            }
            throw error
        }
    }

    private func startAuthenticationTask(_ operation: @escaping () async throws -> Void) {
        authenticationTask?.cancel()
        let taskID = UUID()
        authenticationTaskID = taskID
        authenticationTask = Task { @MainActor in
            defer {
                if authenticationTaskID == taskID {
                    authenticationTask = nil
                    authenticationTaskID = nil
                }
            }
            do {
                try await operation()
            } catch is CancellationError {
            } catch {
                // performAuthenticationRequest owns auth error presentation.
            }
        }
    }

    func signOut() {
        clearLoginCredentials()
        Current.network.signout()
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
            prepareForHelperAction { [weak self] userConsented in
                guard userConsented else { return }
                self?.installHelperIfNecessary(shouldPrepareUserForHelperInstallation: false)
            }
            return
        }

        helperInstallTask?.cancel()
        let taskID = UUID()
        helperInstallTaskID = taskID
        helperInstallTask = Task { @MainActor in
            defer {
                if helperInstallTaskID == taskID {
                    helperInstallTask = nil
                    helperInstallTaskID = nil
                }
            }
            do {
                try await installHelperIfNecessaryAsync()
            } catch is CancellationError {
            } catch {
                self.error = error
                self.presentedAlert = .generic(title: localizeString("Alert.PrivilegedHelper.Error.Title"), message: error.legibleLocalizedDescription)
            }
        }
    }

    func installHelperIfNecessaryAsync() async throws {
        if helperInstallState == .unknown {
            await checkIfHelperIsInstalled()
            try Task.checkCancellation()
        }

        if helperInstallState == .notInstalled {
            try Task.checkCancellation()
            try await Current.helper.install()
            try Task.checkCancellation()
            await checkIfHelperIsInstalled()
        }
    }

    private func checkIfHelperIsInstalled() async {
        helperInstallState = .unknown

        let installed = (try? await Current.helper.checkIfLatestHelperIsInstalledAsync()) ?? false
        helperInstallState = installed ? .installed : .notInstalled
    }

    @discardableResult
    func prepareForHelperAction(preparationID: UUID = UUID(), _ action: @escaping (Bool) -> Void) -> UUID {
        helperActionPreparationID = preparationID
        var didHandleResponse = false
        isPreparingUserForActionRequiringHelper = { [weak self] userConsented in
            guard let self else { return }
            guard self.helperActionPreparationID == preparationID else { return }
            guard didHandleResponse == false else { return }
            didHandleResponse = true
            helperActionPreparationID = nil
            isPreparingUserForActionRequiringHelper = nil
            action(userConsented)
        }
        presentedAlert = .privilegedHelper
        return preparationID
    }

    func respondToPreparedHelperAction(userConsented: Bool) {
        let helperAction = isPreparingUserForActionRequiringHelper
        helperAction?(userConsented)
        presentedAlert = nil
    }

    // MARK: - Install

    func checkMinVersionAndInstall(id: XcodeID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        switch compatibilityStatus(for: availableXcode) {
        case .supported:
            break
        case let .unsupported(_, currentMacOSVersion):
            self.presentedAlert = .checkMinSupportedVersion(xcode: availableXcode, macOS: currentMacOSVersion)
            return
        }

        switch self.dataSource {
        case .apple:
            install(id: id)
        case .xcodeReleases:
            install(id: id)
        }
    }

    func hasMinSupportedOS(requiredMacOSVersion: String) -> Bool {
        compatibilityStatus(requiredMacOSVersion: requiredMacOSVersion).isUnsupported
    }

    private func compatibilityStatus(for availableXcode: AvailableXcode) -> XcodeCompatibilityStatus {
        XcodeCompatibilityService().status(
            for: availableXcode,
            currentOSVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
    }

    private func compatibilityStatus(requiredMacOSVersion: String) -> XcodeCompatibilityStatus {
        XcodeCompatibilityService().status(
            requiredMacOSVersion: requiredMacOSVersion,
            currentOSVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
    }

    func install(id: XcodeID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        installationTasks[id]?.cancel()
        let installationTaskID = UUID()
        installationTaskIDs[id] = installationTaskID
        installationTasks[id] = Task { @MainActor in
            defer {
                if installationTaskIDs[id] == installationTaskID {
                    installationTasks[id] = nil
                    installationTaskIDs[id] = nil
                }
            }
            do {
                setInstallationStep(of: availableXcode.version, to: .authenticating)
                try await signInIfNeededAsync()
                try await waitForAuthenticationTerminalState()
                try await validateDeveloperDownloads()
                _ = try await installAsync(.version(availableXcode), downloader: Downloader(rawValue: Current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2, attemptNumber: 0)
            } catch is CancellationError {
            } catch {
                handleInstallError(error, id: id)
            }
        }
    }

    private func validateDeveloperDownloads() async throws {
        do {
            try await XcodeListService { request in
                try await Current.network.dataTaskAsync(with: request)
            }.validateDeveloperDownloads(missingDownloadsMessage: localizeString("DownloadingError"))
        } catch let error as XcodeListService.Error {
            switch error {
            case let .invalidResult(resultString):
                throw AuthenticationError.invalidResult(resultString: resultString)
            }
        }
    }

    /// Skips using the username/password to log in to Apple, and simply gets a Auth Cookie used in downloading
    /// As of Nov 2022 this was returning a 403 forbidden
    func installWithoutLogin(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        installationTasks[id]?.cancel()
        let installationTaskID = UUID()
        installationTaskIDs[id] = installationTaskID
        installationTasks[id] = Task { @MainActor in
            defer {
                if installationTaskIDs[id] == installationTaskID {
                    installationTasks[id] = nil
                    installationTaskIDs[id] = nil
                }
            }
            do {
                _ = try await installAsync(.version(availableXcode), downloader: Downloader(rawValue: Current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2, attemptNumber: 0)
            } catch is CancellationError {
            } catch {
                handleInstallError(error, id: id)
            }
        }
    }

    func cancelInstall(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        installationTasks[id]?.cancel()
        installationTasks[id] = nil
        installationTaskIDs[id] = nil

        resetDockProgressTracking()

        // If the download is cancelled by the user, clean up the download files that aria2 creates.
        // This isn't done as part of the publisher with handleEvents(receiveCancel:) because it shouldn't happen when e.g. the app quits.
        ArchiveCancellationCleanupService(
            removeItem: { try Current.files.removeItem(at: $0) }
        ).cleanupXcodeArchive(
            for: availableXcode,
            applicationSupportPath: .xcodesApplicationSupport
        )

        if let index = allXcodes.firstIndex(where: { $0.id == id }) {
            allXcodes[index].installState = .notInstalled
        }
    }

    // MARK: - Uninstall
    func uninstall(xcode: Xcode) {
        guard let installedXcodePath = xcode.installedPath else { return }

        uninstallTask?.cancel()
        let taskID = UUID()
        uninstallTaskID = taskID
        uninstallTask = Task { @MainActor in
            defer {
                if uninstallTaskID == taskID {
                    uninstallTask = nil
                    uninstallTaskID = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await uninstallXcodeAsync(path: installedXcodePath)
                try Task.checkCancellation()
                await updateSelectedXcodePathAsync()
            } catch is CancellationError {
            } catch {
                self.error = error
                self.presentedAlert = .generic(title: localizeString("Alert.Uninstall.Error.Title"), message: error.legibleLocalizedDescription)
            }
        }
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
    /// The way this is done is a little roundabout, because it requires user interaction in an alert before the selection task is started.
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
            prepareForHelperAction { [weak self] userConsented in
                guard userConsented else { return }
                self?.select(xcode: xcode, shouldPrepareUserForHelperInstallation: false)
            }
            return
        }

        guard
            var installedXcodePath = xcode.installedPath
        else { return }

        if onSelectActionType == .rename {
            guard let newDestinationXcodePath = renameToXcode(xcode: xcode) else { return }
            installedXcodePath = newDestinationXcodePath
        }

        selectTask?.cancel()
        let taskID = UUID()
        selectTaskID = taskID
        selectTask = Task { @MainActor in
            defer {
                if selectTaskID == taskID {
                    selectTask = nil
                    selectTaskID = nil
                }
            }
            do {
                try await installHelperIfNecessaryAsync()
                try Task.checkCancellation()
                try await Current.helper.switchXcodePathAsync(installedXcodePath.string)
                try Task.checkCancellation()
                await updateSelectedXcodePathAsync()
                if createSymLinkOnSelect && onSelectActionType != .rename {
                    createSymbolicLink(to: installedXcodePath)
                }
            } catch is CancellationError {
            } catch {
                self.error = error
                self.presentedAlert = .generic(title: localizeString("Alert.Select.Error.Title"), message: error.legibleLocalizedDescription)
            }
        }
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
            Logger.appState.error("\(xcode.id.version) is not installed")
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
        createSymbolicLink(to: installedXcodePath, isBeta: isBeta)
    }

    func createSymbolicLink(to installedXcodePath: Path, isBeta: Bool = false) {
        let destinationPath = Path.installDirectory/"Xcode\(isBeta ? "-Beta" : "").app"

        do {
            let service = XcodeSelectionFilesystemService(
                installedXcode: { Current.files.installedXcode(destination: $0) }
            )
            let result = try service.createSymbolicLink(
                to: installedXcodePath,
                in: Path.installDirectory,
                isBeta: isBeta
            )
            if result.replacedExistingSymlink {
                Logger.appState.info("Successfully deleted old symlink")
            }
            Logger.appState.info("Successfully created symbolic link with Xcode\(isBeta ? "-Beta": "").app")
        } catch {
            Logger.appState.error("Unable to create symbolic Link")
            self.error = error
            let message = error as? XcodeSelectionFilesystemError == .destinationExistsAndIsNotSymlink(destinationPath)
                ? localizeString("Alert.SymLink.Message")
                : error.legibleLocalizedDescription
            self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: message)
        }
    }

    func renameToXcode(xcode: Xcode) -> Path? {
        guard let installedXcodePath = xcode.installedPath else { return nil }

        do {
            let service = XcodeSelectionFilesystemService(
                installedXcode: { Current.files.installedXcode(destination: $0) }
            )
            let renamedPath = try service.renameForSelection(
                installedXcodePath: installedXcodePath,
                in: Path.installDirectory
            )
            Logger.appState.debug("Renamed selected Xcode to Xcode.app")
            return renamedPath
        } catch {
            Logger.appState.error("Unable to create rename Xcode.app back to original")
            self.error = error
            // TODO UPDATE MY ERROR STRING
            self.presentedAlert = .generic(title: localizeString("Alert.SymLink.Title"), message: error.legibleLocalizedDescription)
        }
        return nil
    }

    func updateAllXcodes(availableXcodes: [AvailableXcode], installedXcodes: [InstalledXcode], selectedXcodePath: String?) {
        let existingXcodes = allXcodes.map(\.listItem)
        let items = XcodeListComposer().compose(
            availableXcodes: availableXcodes,
            installedXcodes: installedXcodes,
            selectedXcodePath: selectedXcodePath,
            existingXcodes: existingXcodes,
            dataSource: dataSource
        )

        self.allXcodes = items.map { item in
            Xcode(item, icon: item.installedPath.map { NSWorkspace.shared.icon(forFile: $0.string) })
        }
    }


    // MARK: - Private

    private func uninstallXcodeAsync(path: Path) async throws {
        let xcode = InstalledXcode(
            path: path,
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            loadArchitectures: Current.shell.archs
        )!
        _ = try XcodeUninstallService(
            removeItem: { url in try Current.files.removeItem(at: url) },
            trashItem: { url in try Current.files.trashItem(at: url) }
        ).uninstall(xcode, emptyTrash: false)
    }

    private func waitForAuthenticationTerminalState() async throws {
        func validate(_ state: AuthenticationState) throws -> Bool {
            switch state {
            case .authenticated:
                return true
            case .unauthenticated:
                throw AuthenticationError.invalidSession
            case .notAppleDeveloper:
                throw AuthenticationError.notDeveloperAppleId
            case .waitingForFederatedAuthentication:
                return false
            case .waitingForSecondFactor:
                return false
            }
        }

        try Task.checkCancellation()
        if try validate(authenticationState) { return }

        for await state in $authenticationState.values {
            try Task.checkCancellation()
            if try validate(state) { return }
        }
    }

    private func handleInstallError(_ error: Error, id: XcodeID) {
        // Prevent setting the app state error if it is an invalid session, we will present the sign in view instead
        if let error = error as? AuthenticationError, case .notAuthorized = error {
            self.error = error
            self.presentedAlert = .unauthenticated

        } else if error as? AuthenticationError != .invalidSession {
            self.error = error
            self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
        }
        if let index = self.allXcodes.firstIndex(where: { $0.id == id }) {
            self.allXcodes[index].installState = .notInstalled
        }
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
