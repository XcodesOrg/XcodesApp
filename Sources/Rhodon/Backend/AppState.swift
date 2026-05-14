import AppKit
import AppleAPI
import DockProgress
import Observation
import os.log
import Path
import Version
import RhodonKit

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
    case hideSupportRhodon
    case xcodeListArchitectures

    func isManaged() -> Bool {
        UserDefaults.standard.objectIsForced(forKey: rawValue)
    }
}

@MainActor
@Observable
class AppState: @unchecked Sendable {
    let authenticationStore: AuthenticationStore
    let runtimeService = RuntimeService()

    // MARK: - Published Properties

    var availableRhodon: [AvailableXcode] = [] {
        willSet {
            if newValue.count > availableRhodon.count, availableRhodon.count != 0 {
                current.notificationManager.scheduleNotification(
                    title: "New Xcode versions",
                    body: "New Xcode versions are available to download.",
                    category: .normal
                )
            }
            updateAllRhodon(
                availableRhodon: newValue,
                installedRhodon: current.files.installedRhodon(Path.installDirectory),
                selectedXcodePath: selectedXcodePath
            )
        }
        didSet {
            autoInstallIfNeeded()
        }
    }

    var allRhodon: [Xcode] = []
    var selectedXcodePath: String? {
        willSet {
            updateAllRhodon(
                availableRhodon: availableRhodon,
                installedRhodon: current.files.installedRhodon(Path.installDirectory),
                selectedXcodePath: newValue
            )
        }
    }

    @ObservationIgnored var updateTask: Task<Void, Never>?
    var isUpdating: Bool {
        updateTask != nil
    }

    var presentedSheet: RhodonSheet?
    var xcodeBeingConfirmedForUninstallation: Xcode?
    var presentedAlert: RhodonAlert?
    var presentedPreferenceAlert: RhodonPreferencesAlert?
    var helperInstallState: HelperInstallState = .notInstalled
    /// Whether the user is being prepared for the helper installation alert with an explanation.
    /// This closure will be performed after the user chooses whether or not to proceed.
    @ObservationIgnored var isPreparingUserForActionRequiringHelper: ((Bool) async -> Void)?

    // MARK: - Errors

    var error: Error?

    // MARK: Advanced Preferences

    var localPath = "" {
        didSet {
            current.defaults.set(localPath, forKey: "localPath")
        }
    }

    var disableLocalPathChange: Bool {
        PreferenceKey.localPath.isManaged()
    }

    var installPath = "" {
        didSet {
            current.defaults.set(installPath, forKey: "installPath")
        }
    }

    var disableInstallPathChange: Bool {
        PreferenceKey.installPath.isManaged()
    }

    var unxipExperiment = false {
        didSet {
            current.defaults.set(unxipExperiment, forKey: "unxipExperiment")
        }
    }

    var disableUnxipExperiment: Bool {
        PreferenceKey.unxipExperiment.isManaged()
    }

    var createSymLinkOnSelect = false {
        didSet {
            current.defaults.set(createSymLinkOnSelect, forKey: "createSymLinkOnSelect")
        }
    }

    var createSymLinkOnSelectDisabled: Bool {
        onSelectActionType == .rename || PreferenceKey.createSymLinkOnSelect.isManaged()
    }

    var onSelectActionType = SelectedActionType.none {
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

    var showOpenInRosettaOption = false {
        didSet {
            current.defaults.set(showOpenInRosettaOption, forKey: "showOpenInRosettaOption")
        }
    }

    // MARK: - Runtimes

    var downloadableRuntimes: [DownloadableRuntime] = []
    var installedRuntimes: [CoreSimulatorImage] = []

    // MARK: - Tasks

    @ObservationIgnored var installationTasks: [XcodeID: Task<Void, Never>] = [:]
    @ObservationIgnored var runtimeTasks: [String: Task<Void, any Error>] = [:]
    @ObservationIgnored var selectTask: Task<Void, Never>?
    @ObservationIgnored var uninstallTask: Task<Void, Never>?
    @ObservationIgnored private var autoInstallTimer: Timer?

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

        guard let finishDate = formatter.date(from: "11/06/2022") else {
            return ""
        }

        if Date().compare(finishDate) == .orderedAscending {
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
            switch state {
            case .authenticated, .unauthenticated, .notAppleDeveloper:
                self?.presentedSheet = nil
            case .waitingForSecondFactor:
                break
            }
        }

        guard !isTesting else { return }
        try? loadCachedAvailableRhodon()
        try? loadCacheDownloadableRuntimes()
        Task { await checkIfHelperIsInstalled() }
        setupAutoInstallTimer()
        setupDefaults()
    }

    func setupDefaults() {
        localPath = current.defaults.string(forKey: "localPath") ?? Path.defaultRhodonApplicationSupport.string
        unxipExperiment = current.defaults.bool(forKey: "unxipExperiment") ?? false
        createSymLinkOnSelect = current.defaults.bool(forKey: "createSymLinkOnSelect") ?? false
        onSelectActionType = SelectedActionType(rawValue: current.defaults
            .string(forKey: "onSelectActionType") ?? "none") ?? .none
        installPath = current.defaults.string(forKey: "installPath") ?? Path.defaultInstallDirectory.string
        showOpenInRosettaOption = current.defaults.bool(forKey: "showOpenInRosettaOption") ?? false
    }

    // MARK: Timer

    /// Runs a timer every 6 hours when app is open to check if it needs to auto install any rhodon
    func setupAutoInstallTimer() {
        guard
            let storageValue = current.defaults.get(forKey: "autoInstallation") as? Int,
            let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }

        if autoInstallType == .none { return }

        autoInstallTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60 * 6, repeats: true) { [weak self] _ in
            Task {
                await self?.updateIfNeeded()
            }
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
