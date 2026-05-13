import AppKit
import AppleAPI
import Combine
import DockProgress
import os.log
import Path
import Version
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

    func isManaged() -> Bool {
        UserDefaults.standard.objectIsForced(forKey: rawValue)
    }
}

class AppState: ObservableObject, @unchecked Sendable {
    let authenticationStore: AuthenticationStore
    let runtimeService = RuntimeService()

    // MARK: - Published Properties

    @Published var availableXcodes: [AvailableXcode] = [] {
        willSet {
            if newValue.count > availableXcodes.count, availableXcodes.count != 0 {
                current.notificationManager.scheduleNotification(
                    title: "New Xcode versions",
                    body: "New Xcode versions are available to download.",
                    category: .normal
                )
            }
            updateAllXcodes(
                availableXcodes: newValue,
                installedXcodes: current.files.installedXcodes(Path.installDirectory),
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
                installedXcodes: current.files.installedXcodes(Path.installDirectory),
                selectedXcodePath: newValue
            )
        }
    }

    @Published var updatePublisher: AnyCancellable?
    var isUpdating: Bool {
        updatePublisher != nil
    }

    @Published var presentedSheet: XcodesSheet?
    @Published var xcodeBeingConfirmedForUninstallation: Xcode?
    @Published var presentedAlert: XcodesAlert?
    @Published var presentedPreferenceAlert: XcodesPreferencesAlert?
    @Published var helperInstallState: HelperInstallState = .notInstalled
    /// Whether the user is being prepared for the helper installation alert with an explanation.
    /// This closure will be performed after the user chooses whether or not to proceed.
    @Published var isPreparingUserForActionRequiringHelper: ((Bool) -> Void)?

    // MARK: - Errors

    @Published var error: Error?

    // MARK: Advanced Preferences

    @Published var localPath = "" {
        didSet {
            current.defaults.set(localPath, forKey: "localPath")
        }
    }

    var disableLocalPathChange: Bool {
        PreferenceKey.localPath.isManaged()
    }

    @Published var installPath = "" {
        didSet {
            current.defaults.set(installPath, forKey: "installPath")
        }
    }

    var disableInstallPathChange: Bool {
        PreferenceKey.installPath.isManaged()
    }

    @Published var unxipExperiment = false {
        didSet {
            current.defaults.set(unxipExperiment, forKey: "unxipExperiment")
        }
    }

    var disableUnxipExperiment: Bool {
        PreferenceKey.unxipExperiment.isManaged()
    }

    @Published var createSymLinkOnSelect = false {
        didSet {
            current.defaults.set(createSymLinkOnSelect, forKey: "createSymLinkOnSelect")
        }
    }

    var createSymLinkOnSelectDisabled: Bool {
        onSelectActionType == .rename || PreferenceKey.createSymLinkOnSelect.isManaged()
    }

    @Published var onSelectActionType = SelectedActionType.none {
        didSet {
            current.defaults.set(onSelectActionType.rawValue, forKey: "onSelectActionType")

            if onSelectActionType == .rename {
                createSymLinkOnSelect = false
            }
        }
    }

    var onSelectActionTypeDisabled: Bool {
        PreferenceKey.onSelectActionType.isManaged()
    }

    @Published var showOpenInRosettaOption = false {
        didSet {
            current.defaults.set(showOpenInRosettaOption, forKey: "showOpenInRosettaOption")
        }
    }

    @Published var terminateAfterLastWindowClosed = false {
        didSet {
            current.defaults.set(terminateAfterLastWindowClosed, forKey: "terminateAfterLastWindowClosed")
        }
    }

    // MARK: - Runtimes

    @Published var downloadableRuntimes: [DownloadableRuntime] = []
    @Published var installedRuntimes: [CoreSimulatorImage] = []

    // MARK: - Publisher Cancellables

    var cancellables = Set<AnyCancellable>()
    var installationPublishers: [XcodeID: AnyCancellable] = [:]
    var installationTasks: [XcodeID: Task<Void, Never>] = [:]
    var runtimePublishers: [String: Task<Void, any Error>] = [:]
    var selectPublisher: AnyCancellable?
    var uninstallPublisher: AnyCancellable?
    private var autoInstallTimer: Timer?

    // MARK: - Dock Progress Tracking

    static let totalProgressUnits = Int64(10)
    static let unxipProgressWeight = Int64(1)
    var overallProgress = Progress()
    var unxipProgress = {
        let progress = Progress(totalUnitCount: totalProgressUnits)
        progress.kind = .file
        progress.fileOperationKind = .copying
        return progress
    }()

    // MARK: -

    var dataSource: DataSource {
        current.defaults.string(forKey: "dataSource").flatMap(DataSource.init(rawValue:)) ?? .default
    }

    var bottomStatusBarMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let finishDate = formatter.date(from: "11/06/2022")

        if Date().compare(finishDate!) == .orderedAscending {
            return "👨🏻‍💻👩🏼‍💻 Happy WWDC 2022! 👨🏽‍💻🧑🏻‍💻"
        }
        return ""
    }

    // MARK: - Init

    init(authenticationStore: AuthenticationStore = AuthenticationStore()) {
        self.authenticationStore = authenticationStore
        authenticationStore.onSecondFactorRequired = { [weak self] option, authOptions, sessionData in
            self?.presentedSheet = .twoFactor(.init(
                option: option,
                authOptions: authOptions,
                sessionData: sessionData
            ))
        }
        authenticationStore.onAuthenticationStateChanged = { [weak self] state in
            self?.objectWillChange.send()
            switch state {
            case .authenticated, .unauthenticated, .notAppleDeveloper:
                self?.presentedSheet = nil
            case .waitingForSecondFactor:
                break
            }
        }

        guard !isTesting else { return }
        try? loadCachedAvailableXcodes()
        try? loadCacheDownloadableRuntimes()
        checkIfHelperIsInstalled()
        setupAutoInstallTimer()
        setupDefaults()
    }

    func setupDefaults() {
        localPath = current.defaults.string(forKey: "localPath") ?? Path.defaultXcodesApplicationSupport.string
        unxipExperiment = current.defaults.bool(forKey: "unxipExperiment") ?? false
        createSymLinkOnSelect = current.defaults.bool(forKey: "createSymLinkOnSelect") ?? false
        onSelectActionType = SelectedActionType(rawValue: current.defaults
            .string(forKey: "onSelectActionType") ?? "none") ?? .none
        installPath = current.defaults.string(forKey: "installPath") ?? Path.defaultInstallDirectory.string
        showOpenInRosettaOption = current.defaults.bool(forKey: "showOpenInRosettaOption") ?? false
        terminateAfterLastWindowClosed = current.defaults.bool(forKey: "terminateAfterLastWindowClosed") ?? false
    }

    // MARK: Timer

    /// Runs a timer every 6 hours when app is open to check if it needs to auto install any xcodes
    func setupAutoInstallTimer() {
        guard
            let storageValue = current.defaults.get(forKey: "autoInstallation") as? Int,
            let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }

        if autoInstallType == .none { return }

        autoInstallTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60 * 6, repeats: true) { [weak self] _ in
            self?.updateIfNeeded()
        }
    }

    // MARK: - Nested Types

    struct AlertContent: Identifiable {
        var title: String
        var message: String
        var id: String {
            title + message
        }
    }
}

extension OperatingSystemVersion {
    func versionString() -> String {
        String(majorVersion) + "." + String(minorVersion) + "." + String(patchVersion)
    }
}
