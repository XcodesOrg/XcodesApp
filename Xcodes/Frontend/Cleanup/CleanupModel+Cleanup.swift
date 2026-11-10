import Foundation
import os.log
import XcodesCleanupKit
import XcodesKit

/// Selection estimates, confirmation, revalidation, and confirmed cleanup outcomes.
extension CleanupModel {
    private static let cleanupLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Xcodes", category: "Cleanup")

    private var normalizedSelectedItems: [ScanItem] {
        ((try? result?.normalizedSelection(Array(selected))) ?? []).filter { !isCleaned($0) }
    }

    var selectedCount: Int { selected.count + selectedRuntimes.count }

    var estimatedSavingsBytes: UInt64 {
        (estimate?.estimatedReclaimableBytes ?? 0) + simulatorRuntimes.filter { selectedRuntimes.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var cleanupIncludesDevices: Bool {
        normalizedSelectedItems.contains { classification(for: $0) == .simulatorDevice }
    }

    var cleanupActionTitle: String {
        let items = normalizedSelectedItems
        let devices = items.filter { classification(for: $0) == .simulatorDevice }.count
        let files = items.count - devices
        var actions: [String] = []
        if files > 0 || (devices == 0 && selectedRuntimes.isEmpty) { actions.append("Move to Trash") }
        if devices > 0 { actions.append("Delete Devices") }
        if !selectedRuntimes.isEmpty { actions.append("Remove Runtimes") }
        return actions.joined(separator: " & ")
    }

    func updateEstimate() {
        estimateTask?.cancel(); estimate = nil
        guard !isCleaning, let result, !selected.isEmpty else { isEstimating = false; return }
        isEstimating = true
        let selection = selected
        estimateTask = Task { [weak self] in
            do {
                let estimate = try await SavingsEstimator.estimate(selection: Array(selection), in: result)
                try Task.checkCancellation()
                guard let self, self.selected == selection, self.result?.scanID == result.scanID else { return }
                self.estimate = estimate; self.isEstimating = false
            } catch is CancellationError { }
            catch { self?.isEstimating = false; self?.message = error.localizedDescription }
        }
    }

    func selectableItems(_ items: [ScanItem]) -> [ScanItem] {
        guard !isScanning else { return [] }
        return items.filter { selectionUnavailableReason($0, classification: classification(for: $0)) == nil }
    }

    func setSelected(_ item: ScanItem, selected: Bool) {
        if selected {
            guard !isCleaning, selectionUnavailableReason(item, classification: classification(for: item)) == nil else { return }
            self.selected.insert(item.id)
        } else { self.selected.remove(item.id) }
    }

    func toggleSelection(_ items: [ScanItem]) {
        guard !isCleaning, !isScanning else { return }
        let eligible = Set(selectableItems(items).map(\.id))
        if eligible.isSubset(of: selected) { selected.subtract(eligible) }
        else { selected.formUnion(eligible) }
    }

    func selectionUnavailableReason(_ item: ScanItem, classification: CleanupClassification) -> String? {
        if isScanning || isShowingCachedResults { return "Wait for the scan to finish." }
        if isCleaned(item) { return "This item has already been cleaned up." }
        guard item.status != .depthLimited else { return "Increase the scan depth in Folders before cleanup." }
        guard item.status == .complete else { return "This item could not be fully scanned. Increase the scan depth or allow access, then rescan." }
        if classification == .manageExternally { return "Manage this storage in its owning app or Finder." }
        if classification == .simulatorDevice {
            guard item.kind == .directory else { return "Only simulator device folders can be deleted here." }
            if let reason = simulatorDeletionUnavailableReason(item) { return reason }
        }
        if managedRuntimePaths.contains(where: { $0.contains(item.path) || item.path.contains($0) }) {
            return "Remove simulator runtimes using their runtime checkbox, rather than moving managed files to Trash."
        }
        if protectedPaths.contains(item.path) { return "This system or app-management location cannot be moved to Trash here." }
        return nil
    }

    func blockingReason(_ item: ScanItem, classification: CleanupClassification) -> String? {
        if activityUnavailable { return "Could not check running tools. Retry the scan before cleanup." }
        guard item.status == .complete else { return "This item was not completely scanned. Increase the scan depth or allow access, then rescan before cleanup." }
        if classification == .manageExternally { return "Manage this storage in its owning app or Finder." }
        if classification == .simulatorDevice {
            guard item.kind == .directory else { return "Only simulator device folders can be deleted here." }
            if let reason = simulatorDeletionUnavailableReason(item) { return reason }
            if activeTools.contains("simulator") { return "Quit Simulator before deleting device data." }
        }
        if let appState, !appState.installationTasks.isEmpty || !appState.runtimeTasks.isEmpty {
            // Conservative protection: extraction and installation can touch both downloads and developer storage.
            return "Wait for Xcodes downloads and installations to finish."
        }
        for category in policyCatalog where category.location.contains(item.path) || item.path.contains(category.location) {
            let tools: Set<String>
            switch category.id {
            case "derivedData", "archives", "deviceSupport": tools = ["xcode", "xcodebuild", "swift", "swift-frontend", "clang"]
            case "npm", "nodeModules": tools = ["npm", "node", "pnpm", "yarn"]
            case "cargo": tools = ["cargo", "rustc"]
            case "gradle": tools = ["gradle", "java"]
            case "chromeLeftovers": tools = ["google chrome"]
            default: tools = []
            }
            let running = activeTools.intersection(tools).sorted()
            if !running.isEmpty { return "In use by \(running.joined(separator: ", ")). Stop these processes and try again." }
        }
        if item.path.bytes.split(separator: 47).contains(where: { $0.elementsEqual("node_modules".utf8) }), !activeTools.isDisjoint(with: ["node", "npm", "pnpm", "yarn"]) {
            return "Stop Node.js and package-manager processes before cleanup."
        }
        for app in runningApplications {
            if let path = app.path, item.path.contains(path) { return "Quit \(app.name) before cleanup." }
            if app.bundleID == item.displayName { return "Quit the app that owns this cache before cleanup." }
        }
        if managedRuntimePaths.contains(where: { $0.contains(item.path) || item.path.contains($0) }) {
            return "Remove simulator runtimes using their runtime checkbox, rather than moving managed files to Trash."
        }
        if protectedPaths.contains(item.path) { return "This system or app-management location cannot be moved to Trash here." }
        return nil
    }

    /// Capture the confirmed batch once. Window closure never cancels this app-owned task.
    func cleanSelected(confirmedAssociations: [String: Set<CleanupOperations.SimulatorXcode>], files: Files = Current.files) {
        guard !isCleaning, !isScanning else { return }
        do {
            let items = try result?.normalizedSelection(Array(selected)) ?? []
            let runtimes = simulatorRuntimes.filter { selectedRuntimes.contains($0.id) }
            startCleanup(items: sorted(items), runtimes: runtimes,
                // Device/runtime operations refresh their own inventories immediately before deletion.
                prepare: { await self.refreshRunningTools() },
                performItem: { try await self.cleanItem($0, confirmedAssociations: confirmedAssociations, files: files) },
                performRuntime: { try await self.cleanRuntime($0, confirmedAssociations: confirmedAssociations) })
        } catch { message = error.localizedDescription }
    }

    func stopCleanupAfterCurrentItem() {
        guard isCleaning else { return }
        // Never interrupt a Trash or simctl operation halfway through.
        cleanupProgress?.stopRequested = true
    }

    /// Injected operations keep progress and stop behavior testable without deleting user data.
    func startCleanup(items: [ScanItem], runtimes: [CleanupOperations.SimulatorRuntime],
                      prepare: @escaping @MainActor () async -> Void = {},
                      performItem: @escaping @MainActor (ScanItem) async throws -> Void,
                      performRuntime: @escaping @MainActor (CleanupOperations.SimulatorRuntime) async throws -> Void) {
        guard !isCleaning, !items.isEmpty || !runtimes.isEmpty else { return }
        cleanupNoticeTask?.cancel()
        cleanupProgress = CleanupProgress(totalCount: items.count + runtimes.count)
        isCleaning = true
        message = nil
        estimateTask?.cancel(); estimate = nil; isEstimating = false
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = ContinuousClock.now
            await prepare()
            Self.cleanupLogger.debug("Cleanup preparation: \(startedAt.duration(to: .now).description, privacy: .public)")
            var failures: [String] = []
            var successfulItems: [ScanItemID] = []
            var successfulRuntimes: Set<String> = []
            for item in items {
                guard self.cleanupProgress?.stopRequested == false else { break }
                let action: CleanupProgress.Action = self.classification(for: item) == .simulatorDevice ? .device : .trash
                self.beginCleanupItem(name: self.displayName(item), path: item.path.displayPath, action: action)
                do {
                    try await performItem(item)
                    successfulItems.append(item.id)
                    self.recordCleanupItem(action: action, succeeded: true)
                } catch {
                    failures.append("\(item.displayName): \(error.localizedDescription)")
                    self.recordCleanupItem(action: action, succeeded: false)
                }
            }
            for runtime in runtimes {
                guard self.cleanupProgress?.stopRequested == false else { break }
                self.beginCleanupItem(name: runtime.name, path: runtime.path, action: .runtime)
                do {
                    try await performRuntime(runtime)
                    successfulRuntimes.insert(runtime.id)
                    self.cleanedRuntimes.insert(runtime.id)
                    for path in [runtime.path, runtime.runtimeBundlePath].compactMap({ $0 }) {
                        if let item = (try? FilesystemPath(URL(fileURLWithPath: path))).flatMap({ self.result?.item(at: $0) }) {
                            successfulItems.append(item.id)
                        }
                    }
                    self.recordCleanupItem(action: .runtime, succeeded: true)
                } catch {
                    failures.append("\(runtime.name) (\(runtime.build)): \(error.localizedDescription)")
                    self.recordCleanupItem(action: .runtime, succeeded: false)
                }
            }
            if !successfulRuntimes.isEmpty { self.appState?.updateInstalledRuntimes() }
            self.isCleaning = false
            self.applyCleanupOutcome(items: successfulItems, runtimes: successfulRuntimes)
            self.message = failures.isEmpty ? nil : "Could not clean:\n" + failures.joined(separator: "\n")
            self.cleanupProgress?.currentName = nil
            self.cleanupProgress?.currentPath = nil
            self.cleanupProgress?.isFinished = true
            self.cleanupTask = nil
            Self.cleanupLogger.debug("Cleanup batch: \(startedAt.duration(to: .now).description, privacy: .public), \(self.cleanupProgress?.completedCount ?? 0) processed, \(failures.count) failed")
            self.scheduleCleanupNoticeDismissal()
        }
    }

    private func beginCleanupItem(name: String, path: String, action: CleanupProgress.Action) {
        cleanupProgress?.currentName = name
        cleanupProgress?.currentPath = path
        cleanupProgress?.action = action
    }

    private func recordCleanupItem(action: CleanupProgress.Action, succeeded: Bool) {
        cleanupProgress?.completedCount += 1
        if !succeeded { cleanupProgress?.failureCount += 1 }
        else if action == .trash { cleanupProgress?.movedCount += 1 }
        else { cleanupProgress?.deletedCount += 1 }
    }

    private func scheduleCleanupNoticeDismissal() {
        guard let progress = cleanupProgress, progress.failureCount == 0 else { return }
        cleanupNoticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            guard let self, self.cleanupProgress?.id == progress.id else { return }
            self.cleanupProgress = nil
            self.cleanupNoticeTask = nil
        }
    }

    private func cleanItem(_ item: ScanItem, confirmedAssociations: [String: Set<CleanupOperations.SimulatorXcode>], files: Files) async throws {
        let classification = classification(for: item)
        if let reason = blockingReason(item, classification: classification) { throw XcodesKitError(reason) }
        // Trash validates identity in its worker; simctl validates immediately before deletion.
        if classification == .simulatorDevice {
            let id = item.displayName.uppercased()
            let assessment = await CleanupOperations.assessSimulators(xcodes: await simulatorXcodes())
            applySimulatorAssessment(assessment)
            guard assessment.failedXcodes.isEmpty else { throw CleanupOperationError.associationsChanged }
            try CleanupOperations.validateSimulatorDeletion(id: id, inventory: .init(devices: assessment.devices))
            try CleanupOperations.validateSimulatorAssociations(current: assessment.associations[id] ?? [],
                confirmed: confirmedAssociations[id] ?? [])
            guard let directory = assessment.deletionDirectories[id] else { throw CleanupOperationError.deviceNotRegistered }
            let freshInventory = try await CleanupOperations.simulatorDevices(developerDirectory: directory)
            try CleanupOperations.validateSimulatorRefresh(id: id, assessed: .init(devices: assessment.devices), fresh: freshInventory)
            try await CleanupOperations.validate(item)
            _ = try await CleanupOperations.runSimctl(["delete", id], developerDirectory: directory)
        } else {
            try await CleanupOperations.trash(item, files: files)
        }
    }

    private func cleanRuntime(_ runtime: CleanupOperations.SimulatorRuntime,
                              confirmedAssociations: [String: Set<CleanupOperations.SimulatorXcode>]) async throws {
        await refreshActivity()
        if let reason = runtimeBlockingReason(runtime) { throw XcodesKitError(reason) }
        try CleanupOperations.validateSimulatorAssociations(current: runtimeAssociations[runtime.id] ?? [],
            confirmed: confirmedAssociations["runtime:" + runtime.id] ?? [])
        // Recheck the images after association queries, immediately before removal.
        let freshRuntimes = try await CleanupOperations.simulatorRuntimes()
        let devices = try await CleanupOperations.simulatorDevices()
        try CleanupOperations.validateRuntimeDeletion(runtime, fresh: freshRuntimes, devices: devices)
        _ = try await CleanupOperations.runSimctl(["runtime", "delete", runtime.id])
    }

    var selectedSimulatorAssociations: [String: Set<CleanupOperations.SimulatorXcode>] {
        var associations = Dictionary(uniqueKeysWithValues: normalizedSelectedItems.filter { classification(for: $0) == .simulatorDevice }.map {
            let id = $0.displayName.uppercased()
            return (id, simulatorAssessment?.associations[id] ?? [])
        })
        for id in selectedRuntimes { associations["runtime:" + id] = runtimeAssociations[id] ?? [] }
        return associations
    }

    var cleanupConfirmationMessage: String {
        guard cleanupIncludesDevices || !selectedRuntimes.isEmpty else { return "The selected items will be moved to Trash." }
        var counts: [CleanupOperations.SimulatorXcode: Int] = [:]
        for associations in selectedSimulatorAssociations.values {
            for xcode in associations { counts[xcode, default: 0] += 1 }
        }
        let warnings = counts.sorted { $0.key.developerDirectory < $1.key.developerDirectory }.map { xcode, count in
            "\(count) selected item(s) are associated with \(xcode.selected ? "selected" : "installed") \(xcode.name)."
        }
        var messages: [String] = []
        if normalizedSelectedItems.contains(where: { classification(for: $0) != .simulatorDevice }) { messages.append("Ordinary files will move to Trash.") }
        if cleanupIncludesDevices { messages.append("Selected simulator devices will be permanently deleted, including their apps and data. This cannot be undone.") }
        if !selectedRuntimes.isEmpty { messages.append("Selected OS runtimes will be uninstalled. Devices using these OS versions may become unavailable until their runtime is reinstalled.") }
        return (messages + warnings).joined(separator: "\n\n")
    }

    /// Keep the immutable scan snapshot and subtract confirmed successes from its presentation.
    /// Failed items and the current filter/disclosure state remain available for review or retry.
    func applyCleanupOutcome(items: [ScanItemID], runtimes: Set<String>) {
        estimateTask?.cancel(); estimate = nil; isEstimating = false
        var removed = cleanedItems.union(items)
        if let result {
            for runtime in simulatorRuntimes where runtimes.contains(runtime.id) {
                for path in [runtime.path, runtime.runtimeBundlePath].compactMap({ $0 }) {
                    if let item = (try? FilesystemPath(URL(fileURLWithPath: path))).flatMap({ result.item(at: $0) }) { removed.insert(item.id) }
                }
            }
            let roots = (try? result.normalizedSelection(Array(removed))) ?? []
            cleanedItems = Set(roots.map(\.id))
            cleanedBytes = [:]
            for item in roots {
                for ancestor in [item] + result.ancestors(of: item.id) {
                    cleanedBytes[ancestor.id, default: 0] += item.allocatedBytes
                }
            }
        }
        cleanedRuntimes.formUnion(runtimes)
        simulatorRuntimes.removeAll { cleanedRuntimes.contains($0.id) }
        for id in runtimes { runtimeAssociations.removeValue(forKey: id) }
        selected = Set(selected.filter { id in result?.item(id).map { !isCleaned($0) } ?? false })
        selectedRuntimes.subtract(cleanedRuntimes)
        findings.removeAll { finding in finding.itemIDs.allSatisfy { id in result?.item(id).map(isCleaned) ?? true } }
        rebuildSections()
        sections.sort { $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes }
        applyOSFilter()
        updateEstimate()
        refreshAvailableCleanupBytes()
    }

    func isCleaned(_ item: ScanItem) -> Bool {
        if cleanedItems.isEmpty { return false }
        if cleanedItems.contains(item.id) { return true }
        var parent = item.parentID
        while let id = parent {
            if cleanedItems.contains(id) { return true }
            parent = result?.item(id)?.parentID
        }
        return false
    }

    func displayedBytes(for item: ScanItem) -> UInt64 {
        if isShowingCachedResults, let bytes = cachedItemBytes[item.id] { return bytes }
        if isCleaned(item) { return 0 }
        let removed = cleanedBytes[item.id] ?? 0
        return item.allocatedBytes - min(item.allocatedBytes, removed)
    }
}
