import Foundation
import Path
import XcodesCleanupKit
import XcodesKit

/// Editable folder configuration, migration, and shared catalog resolution.
extension CleanupModel {
    /// Restore legacy preferences, then let the editable JSON take precedence.
    func restoreFolderConfiguration() {
        if let saved = folderDefaults.get(Self.scanDepthKey) as? Int, saved >= 0 { scanDepth = saved }
        excludedFolders = Set(folderDefaults.get(Self.excludedFoldersKey) as? [String] ?? [])
        if let data = folderDefaults.get(Self.foldersKey) as? Data,
           let saved = try? JSONDecoder().decode([CleanupFolder].self, from: data),
           let normalized = try? CleanupFolder.normalized(saved) { folders = normalized }
        if let url = folderConfigurationURL {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try reloadFolderConfiguration(invalidateResults: false)
                } else {
                    // One-time migration from preferences; existing JSON always takes precedence.
                    try persistFolderConfiguration(folders: folders, excluded: excludedFolders, depth: scanDepth)
                }
            } catch { message = "Could not load cleanup-folders.json: " + error.localizedDescription }
        }
    }

    private static let scanDepthKey = "cleanup.scanDepth.v1"

    private static let foldersKey = "cleanup.scanFolders.v1"

    private static let excludedFoldersKey = "cleanup.excludedFolders.v1"

    private var folderConfigurationURL: URL? {
        configurationURLOverride ?? (usesFileConfiguration ? Path.cleanupFoldersFile.url : nil)
    }

    private func persistFolderConfiguration(folders: [CleanupFolder], excluded: Set<String>, depth: Int) throws {
        guard let url = folderConfigurationURL else {
            // In-memory consumers/tests can continue using injected preferences.
            folderDefaults.set(try JSONEncoder().encode(folders), Self.foldersKey)
            folderDefaults.set(excluded.sorted(), Self.excludedFoldersKey)
            folderDefaults.set(depth, Self.scanDepthKey)
            return
        }
        let configuration = CleanupFolder.Configuration(
            developerFolders: suggestedDeveloperFolders.map(\.categoryID).filter { !excluded.contains($0) },
            scanDepth: depth,
            folders: folders.map { .init(id: $0.id, name: $0.name, path: $0.url.path, preset: $0.preset) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        for key in [Self.foldersKey, Self.excludedFoldersKey, Self.scanDepthKey] { folderDefaults.set(nil, key) }
    }

    /// Reload manual edits without writing them back; invalid files leave the current list intact.
    func reloadFolderConfiguration(invalidateResults: Bool = true) throws {
        guard let url = folderConfigurationURL, FileManager.default.fileExists(atPath: url.path) else { return }
        let configuration = try JSONDecoder().decode(CleanupFolder.Configuration.self, from: Data(contentsOf: url))
        let known = Set(suggestedDeveloperFolders.map(\.categoryID))
        guard configuration.version == 1, configuration.scanDepth >= 0,
              Set(configuration.developerFolders).isSubset(of: known) else {
            throw XcodesKitError("Invalid cleanup configuration version, depth, or developer folder category.")
        }
        let normalized = try CleanupFolder.normalized(configuration.folders.map { try $0.folder() })
        let excluded = known.subtracting(configuration.developerFolders)
        guard normalized != folders || excluded != excludedFolders || configuration.scanDepth != scanDepth else { return }
        folders = normalized; excludedFolders = excluded; scanDepth = configuration.scanDepth
        foldersNeedScan = true
        if invalidateResults { invalidateCachedResults() }
    }

    func replaceFolders(_ folders: [CleanupFolder], rescan: Bool = true, persist: Bool = true) throws {
        guard !isCleaning else { return }
        let normalized = try CleanupFolder.normalized(folders)
        guard normalized != self.folders else { return }
        let oldRoots = Set(self.folders.map(\.canonicalPath))
        let newRoots = Set(normalized.map(\.canonicalPath))
        if persist { try persistFolderConfiguration(folders: normalized, excluded: excludedFolders, depth: scanDepth) }
        self.folders = normalized
        if oldRoots != newRoots { foldersNeedScan = true; invalidateCachedResults() }
        if rescan && oldRoots != newRoots && (hasStarted || cleanupWindowOpen) { scan() }
        else {
            configureScan(categories: try makeCatalog(), policyCategories: try makeCatalog(includeAllPolicies: true))
            rebuildSections(); applyOSFilter(); resolveOSMetadata()
            refreshAvailableCleanupBytes()
        }
    }

    @discardableResult
    func setScanDepth(_ depth: Int, rescan: Bool = true) -> Bool {
        guard depth >= 0, !isCleaning else { return false }
        if scanDepth != depth {
            do { try persistFolderConfiguration(folders: folders, excluded: excludedFolders, depth: depth) }
            catch { message = error.localizedDescription; return false }
            scanDepth = depth
            invalidateCachedResults()
            foldersNeedScan = true
        }
        if rescan && foldersNeedScan && (hasStarted || cleanupWindowOpen) { scan() }
        return true
    }

    private func developerCatalog() throws -> [FindingCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xcodeDefaults = UserDefaults(suiteName: "com.apple.dt.Xcode")
        let custom = xcodeDefaults?.string(forKey: "IDECustomDerivedDataLocation")
        let derivedData = custom.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return try FindingCatalog.developer(home: home, derivedData: derivedData, xcodesDownloads: Path.xcodesApplicationSupport.url)
    }

    var suggestedDeveloperFolders: [CleanupFolder] {
        // The package owns defaults, titles, paths, and management hints; the app only adapts them for its UI.
        ((try? developerCatalog()) ?? []).map { category in
            CleanupFolder(id: CleanupFolder.stableIdentifier(for: "category:" + category.id),
                name: category.title, url: category.location.url, preset: nil, builtInCategoryID: category.id)
        }
    }

    var scanFolders: [CleanupFolder] {
        suggestedDeveloperFolders.filter { !excludedFolders.contains($0.categoryID) } + folders
    }

    func replaceScanFolders(_ entries: [CleanupFolder], rescan: Bool = true) throws {
        guard !isCleaning else { return }
        let normalized = try CleanupFolder.normalized(entries)
        let known = Set(suggestedDeveloperFolders.map(\.categoryID))
        let included = Set(normalized.compactMap(\.builtInCategoryID))
        let excluded = known.subtracting(included)
        let changed = excluded != excludedFolders
        let custom = normalized.filter { $0.builtInCategoryID == nil }
        // Commit the JSON atomically before publishing the new folder list.
        try persistFolderConfiguration(folders: custom, excluded: excluded, depth: scanDepth)
        excludedFolders = excluded
        try replaceFolders(custom, rescan: false, persist: false)
        if changed { foldersNeedScan = true; invalidateCachedResults() }
        if excludedFolders.contains("simulatorRuntimes") { simulatorRuntimes = []; selectedRuntimes = [] }
        configureScan(categories: try makeCatalog(), policyCategories: try makeCatalog(includeAllPolicies: true))
        rebuildSections(); applyOSFilter(); resolveOSMetadata()
        refreshAvailableCleanupBytes()
        if rescan && foldersNeedScan && (hasStarted || cleanupWindowOpen) { scan() }
    }

    func makeCatalog(includeAllPolicies: Bool = false) throws -> [FindingCategory] {
        var categories = try developerCatalog().filter {
            includeAllPolicies || (!$0.requiresManagedInventory && !excludedFolders.contains($0.id))
        }
        categories += try folders.map { try $0.category() }
        if includeAllPolicies {
            let temp = FileManager.default.temporaryDirectory.deletingLastPathComponent()
            categories += try FindingCatalog.general(home: FileManager.default.homeDirectoryForCurrentUser, userTemporaryDirectory: temp)
        }
        return categories
    }
}
