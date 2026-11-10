import Combine
import Foundation
import XcodesCleanupKit

/// Shared state for the app's cleanup window and status bar. All extensions remain main-actor isolated.
/// Scan, cache, configuration, and cleanup behavior live in their named companion files.
@MainActor
final class CleanupModel: ObservableObject {
    // State is internal so the focused extensions can coordinate it across files.

    // MARK: - Scan lifecycle

    @Published var result: ScanResult?
    @Published var findings: [CleanupFinding] = []
    @Published var progress: ScanProgress?
    @Published var isScanning = false
    var hasStarted = false
    var cleanupWindowOpen = false
    var foldersNeedScan = false
    weak var appState: AppState?
    var session: ScanSession?
    var scanTask: Task<Void, Never>?
    var generation = UUID()
    var catalog: [FindingCategory] = []
    var hasConfiguredScope = false
    var policyCatalog: [FindingCategory] = []
    var classificationPolicy = CleanupPolicy(categories: [], findings: [])
    var classificationCache: [ScanItemID: CleanupClassification] = [:]

    // MARK: - Folder configuration

    @Published var folders: [CleanupFolder] = []
    /// 0 means unlimited. Developer locations always retain complete traversal.
    @Published var scanDepth = 1
    @Published var excludedFolders: Set<String> = []
    let folderDefaults: Defaults
    let configurationURLOverride: URL?
    let usesFileConfiguration: Bool

    // MARK: - Completed result cache

    @Published var availableCleanupBytes: UInt64?
    @Published var isShowingCachedResults = false
    @Published var lastScanCompletedAt: Date?
    var cachedScannedBytes: UInt64 = 0
    var cachedItemBytes: [ScanItemID: UInt64] = [:]

    // MARK: - Window presentation and OS metadata

    @Published var sections: [CleanupSectionData] = []
    @Published var visibleSections: [CleanupSectionData] = []
    @Published var operatingSystems: [String] = []
    @Published var selectedOperatingSystem: String? {
        didSet {
            guard oldValue != selectedOperatingSystem else { return }
            selected = []; selectedRuntimes = []
            applyOSFilter()
            updateEstimate()
        }
    }
    var osVersions: [ScanItemID: String] = [:]
    var attemptedOSMetadata: Set<ScanItemID> = []
    var osMetadataTask: Task<Void, Never>?

    // MARK: - Selection and confirmed cleanup

    @Published var selected: Set<ScanItemID> = []
    @Published var estimate: SavingsEstimate?
    @Published var isEstimating = false
    @Published var isCleaning = false
    @Published var cleanupProgress: CleanupProgress?
    @Published var message: String?
    var cleanedItems: Set<ScanItemID> = []
    var cleanedBytes: [ScanItemID: UInt64] = [:]
    var cleanedRuntimes: Set<String> = []
    var estimateTask: Task<Void, Never>?
    var cleanupTask: Task<Void, Never>?
    var cleanupNoticeTask: Task<Void, Never>?

    // MARK: - CoreSimulator inventory and active tools

    @Published var simulatorRuntimes: [CleanupOperations.SimulatorRuntime] = []
    @Published var selectedRuntimes: Set<String> = []
    @Published var runtimeInventoryUnavailable = false
    @Published var runtimeAssociations: [String: Set<CleanupOperations.SimulatorXcode>] = [:]
    @Published var simulatorAssessment: CleanupOperations.SimulatorAssessment?
    @Published var simulatorNames: [String: String] = [:]
    var runtimeAssociationCheckFailed = true
    var managedRuntimePaths: [FilesystemPath] = []
    var savedSimulatorDetails: [String: CleanupOperations.SimulatorDevice] = [:]
    var simulatorNamesTask: Task<Void, Never>?
    var attemptedSimulatorNames: Set<String> = []
    var activityTask: Task<Void, Never>?
    var protectedPaths = CleanupModel.makeProtectedPaths()
    var activityUnavailable = true
    var runningApplications: [(name: String, bundleID: String?, path: FilesystemPath?)] = []
    var activeTools: Set<String> = []

    init(defaults: Defaults = Current.defaults, folderConfigurationURL: URL? = nil, useFileConfiguration: Bool = false) {
        folderDefaults = defaults
        configurationURLOverride = folderConfigurationURL
        usesFileConfiguration = useFileConfiguration
        restoreFolderConfiguration()
        restoreCachedResults()
    }
}
