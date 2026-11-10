import Foundation
import XcodesCleanupKit

/// Completed estimates and presentation snapshots persisted between launches.
extension CleanupModel {
    private static let resultsKey = "cleanup.results.v1"

    // Persist only presentation data; fresh ScanResult identities are required for cleanup.
    private struct CachedResults: Codable {
        let version: Int
        let scope: [String]
        let savedAt: Date
        let lastScanCompletedAt: Date?
        let availableBytes: UInt64
        let scannedBytes: UInt64
        let sections: [CleanupSectionData]
        let runtimes: [CleanupOperations.SimulatorRuntime]
        let devices: [String: CleanupOperations.SimulatorDevice]
        let osVersions: [ScanItemID: String]
        let itemBytes: [ScanItemID: UInt64]
    }

    /// Cached rows are presentation only; cleanup still requires a fresh scan.
    func restoreCachedResults() {
        guard let data = folderDefaults.get(Self.resultsKey) as? Data,
              let cache = try? JSONDecoder().decode(CachedResults.self, from: data),
              cache.version == 1, cache.scope == cacheScope else { return }
        availableCleanupBytes = cache.availableBytes
        lastScanCompletedAt = cache.lastScanCompletedAt ?? cache.savedAt
        cachedScannedBytes = cache.scannedBytes
        sections = cache.sections; visibleSections = cache.sections
        simulatorRuntimes = cache.runtimes
        managedRuntimePaths = cache.runtimes.flatMap(\.managedPaths).compactMap { try? FilesystemPath(URL(fileURLWithPath: $0)) }
        savedSimulatorDetails = cache.devices; osVersions = cache.osVersions
        cachedItemBytes = cache.itemBytes
        isShowingCachedResults = true
        if let categories = try? makeCatalog(), let policies = try? makeCatalog(includeAllPolicies: true) {
            configureScan(categories: categories, policyCategories: policies)
        }
    }

    // Reuse cached results only for the same folders, configured paths, and depth.
    private var cacheScope: [String] {
        ["depth:\(scanDepth)"] + scanFolders.map { $0.categoryID + ":" + $0.url.standardizedFileURL.path }.sorted()
    }

    func saveCachedResults() {
        guard !isScanning, !foldersNeedScan, !isShowingCachedResults,
              let availableCleanupBytes else { return }
        let cache = CachedResults(version: 1, scope: cacheScope, savedAt: Date(), lastScanCompletedAt: lastScanCompletedAt,
            availableBytes: availableCleanupBytes, scannedBytes: totalScannedBytes,
            sections: sections, runtimes: simulatorRuntimes,
            devices: savedSimulatorDetails.merging(simulatorAssessment?.devices ?? [:]) { _, current in current },
            osVersions: osVersions,
            itemBytes: Dictionary(sections.flatMap(\.items).map { ($0.id, displayedBytes(for: $0)) }, uniquingKeysWith: { first, _ in first }))
        if let data = try? JSONEncoder().encode(cache) { folderDefaults.set(data, Self.resultsKey) }
    }

    func invalidateCachedResults() {
        folderDefaults.set(nil, Self.resultsKey)
        availableCleanupBytes = nil
        if isShowingCachedResults {
            sections = []; visibleSections = []; simulatorRuntimes = []
            cachedScannedBytes = 0; cachedItemBytes = [:]; isShowingCachedResults = false
        }
    }

    /// Occupied bytes eligible for cleanup, independent of selections and OS filters.
    /// This is a fast scan-based estimate; selected-item APFS accounting stays in updateEstimate().
    func refreshAvailableCleanupBytes() {
        guard !isScanning, !isShowingCachedResults, !foldersNeedScan, result?.progress.phase == .completed || (result == nil && availableCleanupBytes != nil) else { return }
        let eligible = selectableItems(sections.flatMap(\.items))
        let normalized = (try? result?.normalizedSelection(eligible.map(\.id))) ?? []
        let files = normalized.reduce(UInt64(0)) { $0 + displayedBytes(for: $1) }
        let runtimes = simulatorRuntimes.filter { runtimeSelectionUnavailableReason($0) == nil }
            .reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let total = files + runtimes
        if availableCleanupBytes != total { availableCleanupBytes = total }
        saveCachedResults()
    }

    var totalScannedBytes: UInt64 {
        if isShowingCachedResults { return cachedScannedBytes }
        let original = progress?.allocatedBytes ?? result?.progress.allocatedBytes ?? 0
        let removed = cleanedItems.compactMap { result?.item($0) }.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
        let scanned = original - min(original, removed)
        return scanned + simulatorRuntimes.filter { runtime in
            // Do not add managed image bytes again if they were already scanned through a chosen folder.
            ![runtime.path, runtime.parentImagePath].compactMap { $0 }.contains { path in
                (try? FilesystemPath(URL(fileURLWithPath: path))).flatMap { result?.item(at: $0) } != nil
            }
        }.reduce(0) { $0 + $1.sizeBytes }
    }
}
