import Foundation
import XcodesCleanupKit

/// Prepared rows, display values, and OS filtering for the cleanup window.
extension CleanupModel {
    var simulatorRuntimeCategory: FindingCategory? {
        policyCatalog.first { $0.id == "simulatorRuntimes" }
    }

    var visibleRuntimes: [CleanupOperations.SimulatorRuntime] {
        guard !excludedFolders.contains("simulatorRuntimes") else { return [] }
        return simulatorRuntimes.filter { selectedOperatingSystem == nil || CleanupOSMetadata.filterName($0.name) == selectedOperatingSystem }
    }

    var listSections: [CleanupListSection] {
        var values = visibleSections.map(CleanupListSection.files)
        if !visibleRuntimes.isEmpty { values.append(.runtimes(visibleRuntimes.reduce(0) { $0 + $1.sizeBytes })) }
        if !isScanning { values.sort { $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes } }
        return values
    }

    func rebuildSections() {
        guard let result else { sections = []; return }
        var prepared: [CleanupSectionData] = []
        for category in catalog {
            guard let root = result.item(at: category.location), !isCleaned(root) else { continue }
            let items = self.items(for: category)
            guard root.status != .scanning || !items.isEmpty else { continue }
            let size = category.id == "xcodesDownloads" || root.status == .scanning
                ? items.reduce(UInt64(0)) { $0 + displayedBytes(for: $1) } : displayedBytes(for: root)
            let folder = folders.first { $0.categoryID == category.id }
            prepared.append(CleanupSectionData(id: "category:" + category.id, title: category.title,
                locations: [category.location.url], allocatedBytes: size, items: items,
                explanation: category.classification == .review || category.classification == .manageExternally ? category.explanation : nil,
                incomplete: root.status != .complete && root.status != .scanning,
                accessDenied: result.hasAccessDeniedEntries(in: root.id),
                osCategory: folder?.preset?.rawValue))
        }
        for finding in findings where finding.categoryID == "nodeModules" {
            let items = items(for: finding)
            guard !items.isEmpty else { continue }
            if hasConfiguredScope && !items.contains(where: { item in catalog.contains { $0.location.contains(item.path) } }) { continue }
            prepared.append(CleanupSectionData(id: "finding:" + finding.id, title: finding.title,
                locations: locations(for: finding), allocatedBytes: items.reduce(0) { $0 + displayedBytes(for: $1) },
                items: items, explanation: finding.explanation, incomplete: !finding.isComplete,
                accessDenied: finding.itemIDs.compactMap(result.item).contains { result.hasAccessDeniedEntries(in: $0.id) }))
        }
        // Keep discovery order during scanning; finishScan applies the final size order.
        var remaining = Dictionary(uniqueKeysWithValues: prepared.map { ($0.id, $0) })
        let existing = sections.compactMap { remaining.removeValue(forKey: $0.id) }
        prepared = existing + prepared.filter { remaining[$0.id] != nil }
        sections = prepared
    }

    func items(for category: FindingCategory) -> [ScanItem] {
        completedItems(result?.cleanupItems(for: category) ?? [])
    }

    func completedItems(_ items: [ScanItem]) -> [ScanItem] {
        sorted(items.filter { $0.status != .scanning && !isCleaned($0) })
    }

    func displayName(_ item: ScanItem) -> String {
        if item.displayName == "node_modules", let parent = result?.ancestors(of: item.id).first {
            return parent.displayName + " / node_modules"
        }
        if let id = UUID(uuidString: item.displayName)?.uuidString,
           classification(for: item) == .simulatorDevice {
            return simulatorAssessment?.devices[id]?.model ?? savedSimulatorDetails[id]?.model ?? simulatorNames[id] ?? "Unknown simulator"
        }
        return item.displayName
    }

    func locations(for finding: CleanupFinding) -> [URL] {
        if let category = catalog.first(where: { $0.id == finding.categoryID }) {
            return [category.location.url]
        }
        return finding.itemIDs.compactMap { result?.item($0)?.path.url.deletingLastPathComponent() }
    }

    func items(for finding: CleanupFinding) -> [ScanItem] {
        completedItems(result?.cleanupItems(for: finding) ?? [])
    }

    func sorted(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted {
            let left = displayedBytes(for: $0), right = displayedBytes(for: $1)
            return left == right ? $0.displayName < $1.displayName : left > right
        }
    }

    func classification(for item: ScanItem) -> CleanupClassification {
        if let cached = classificationCache[item.id] { return cached }
        let classification = classificationPolicy.classification(for: item, in: result)
        classificationCache[item.id] = classification
        return classification
    }

    func operatingSystemLabel(_ item: ScanItem) -> String? {
        if classification(for: item) == .simulatorDevice,
           let device = simulatorAssessment?.devices[item.displayName.uppercased()] ?? savedSimulatorDetails[item.displayName.uppercased()] {
            let name = device.runtimeName ?? CleanupOperations.simulatorRuntimeName(device.runtime)
            return CleanupOSMetadata.filterName(name) == nil ? nil : name
        }
        return osVersions[item.id]
    }

    private func osCandidates(_ section: CleanupSectionData) -> [ScanItem] {
        guard section.id == "category:archives", let result else { return section.items }
        // A date folder can contain archives for several OS versions. Filter/select actual archives, never their mixed parent.
        return section.items.flatMap { item in
            item.displayName.hasSuffix(".xcarchive") ? [item] : result.children(of: item.id).filter { $0.displayName.hasSuffix(".xcarchive") && $0.kind == .directory && $0.status != .scanning && !isCleaned($0) }
        }
    }

    func applyOSFilter() {
        let names = sections.flatMap { osCandidates($0) }.compactMap(operatingSystemLabel).compactMap(CleanupOSMetadata.filterName)
            + simulatorRuntimes.compactMap { CleanupOSMetadata.filterName($0.name) }
        let platforms = ["iOS", "visionOS", "watchOS", "tvOS", "macOS"]
        operatingSystems = Set(names).sorted { left, right in
            let leftPlatform = left.split(separator: " ").first.map(String.init) ?? ""
            let rightPlatform = right.split(separator: " ").first.map(String.init) ?? ""
            if leftPlatform != rightPlatform {
                return (platforms.firstIndex(of: leftPlatform) ?? platforms.count) < (platforms.firstIndex(of: rightPlatform) ?? platforms.count)
            }
            return left.compare(right, options: .numeric) == .orderedDescending
        }
        guard let filter = selectedOperatingSystem else { visibleSections = sections; return }
        visibleSections = sections.compactMap { section in
            let items = osCandidates(section).filter { operatingSystemLabel($0).flatMap(CleanupOSMetadata.filterName) == filter }
            guard !items.isEmpty else { return nil }
            return CleanupSectionData(id: section.id, title: section.title, locations: section.locations,
                allocatedBytes: items.reduce(0) { $0 + displayedBytes(for: $1) }, items: sorted(items),
                explanation: section.explanation, incomplete: section.incomplete, accessDenied: section.accessDenied, osCategory: section.osCategory)
        }
        if !isScanning { visibleSections.sort { $0.allocatedBytes > $1.allocatedBytes } }
        selected.formIntersection(visibleSections.flatMap(\.items).map(\.id))
        selectedRuntimes.formIntersection(visibleRuntimes.map(\.id))
    }

    func applyOSMetadata(_ versions: [ScanItemID: String]) {
        osVersions.merge(versions) { _, new in new }
        applyOSFilter()
        saveCachedResults()
    }

    func resolveOSMetadata() {
        guard osMetadataTask == nil else { return }
        let requests = sections.filter { ["category:deviceSupport", "category:archives", "category:backups"].contains($0.id) || $0.osCategory == "backups" }.flatMap { section in
            osCandidates(section).filter { $0.status == .complete && $0.kind == .directory && !attemptedOSMetadata.contains($0.id) }.map {
                (item: $0, category: section.osCategory ?? String(section.id.dropFirst("category:".count)))
            }
        }
        guard !requests.isEmpty else { return }
        attemptedOSMetadata.formUnion(requests.map { $0.item.id })
        let token = generation
        osMetadataTask = Task { [weak self] in
            let versions = await CleanupOSMetadata.read(requests)
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.applyOSMetadata(versions)
            self.osMetadataTask = nil
            self.resolveOSMetadata()
        }
    }
}
