import AppKit
import Foundation
import Path
import XcodesCleanupKit

/// Read-only CoreSimulator inventory, Xcode associations, and active-tool checks.
extension CleanupModel {
    func refreshActivity() async {
        await refreshSimulatorActivity()
        guard !Task.isCancelled else { return }
        await refreshRunningTools()
    }

    private func refreshSimulatorActivity() async {
        let xcodes = await simulatorXcodes()
        let assessment = await CleanupOperations.assessSimulators(xcodes: xcodes)
        guard !Task.isCancelled else { return }
        applySimulatorAssessment(assessment)
        let runtimes = try? await CleanupOperations.simulatorRuntimes()
        guard !Task.isCancelled else { return }
        var associations: [String: Set<CleanupOperations.SimulatorXcode>] = [:]
        var associationFailed = xcodes.isEmpty || !assessment.failedXcodes.isEmpty
        if let runtimes {
            for xcode in xcodes {
                do {
                    let matches = try await CleanupOperations.runtimeMatches(developerDirectory: xcode.developerDirectory)
                    for runtime in runtimes where matches.contains(runtime.build) { associations[runtime.id, default: []].insert(xcode) }
                } catch { associationFailed = true }
                guard !Task.isCancelled else { return }
            }
        }
        applyRuntimeInventory(runtimes ?? [], associations: associations, unavailable: runtimes == nil, associationCheckFailed: associationFailed)
    }

    /// Ordinary Trash operations need active-use checks, not a full CoreSimulator inventory.
    func refreshRunningTools() async {
        protectedPaths = Self.makeProtectedPaths()
        let output = try? await Process.runAsync(URL(fileURLWithPath: "/bin/ps"), ["-axo", "comm="])
        guard !Task.isCancelled else { return }
        activeTools = Set((output?.out ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).lastPathComponent.lowercased() })
        runningApplications = NSWorkspace.shared.runningApplications.map {
            (name: $0.localizedName ?? "the running app", bundleID: $0.bundleIdentifier, path: $0.bundleURL.flatMap { try? FilesystemPath($0) })
        }
        activeTools.formUnion(runningApplications.map { $0.name.lowercased() })
        activityUnavailable = output == nil
        refreshAvailableCleanupBytes()
    }

    /// Launch Services covers Xcodes outside the configured install directory;
    /// the app's installed paths and selected developer directory cover unregistered installs.
    func simulatorXcodes() async -> [CleanupOperations.SimulatorXcode] {
        var urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: "com.apple.dt.Xcode")
        urls += appState?.allXcodes.compactMap { $0.installedPath?.url } ?? []
        var selectedDirectory = appState?.selectedXcodePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedDirectory == nil {
            let output = try? await Process.runAsync(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"])
            selectedDirectory = output?.out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let selectedDirectory { urls.append(URL(fileURLWithPath: selectedDirectory)) }
        var seen: Set<String> = []
        return urls.compactMap { url in
            let developer = url.path.hasSuffix("/Contents/Developer") ? url : url.appendingPathComponent("Contents/Developer")
            let directory = developer.resolvingSymlinksInPath().standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: developer.appendingPathComponent("usr/bin/simctl").path),
                  seen.insert(directory).inserted else { return nil }
            let isSelected = selectedDirectory.map {
                let selected = URL(fileURLWithPath: $0)
                let path = $0.hasSuffix(".app") ? selected.appendingPathComponent("Contents/Developer") : selected
                return path.resolvingSymlinksInPath().standardizedFileURL.path == directory
            } ?? false
            return CleanupOperations.SimulatorXcode(developerDirectory: directory,
                name: developer.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
                selected: isSelected)
        }.sorted { $0.developerDirectory < $1.developerDirectory }
    }

    func applySimulatorAssessment(_ assessment: CleanupOperations.SimulatorAssessment) {
        simulatorAssessment = assessment
        applySimulatorInventory(names: assessment.devices.mapValues(\.name))
        applyOSFilter()
        refreshAvailableCleanupBytes()
    }

    func simulatorDeletionUnavailableReason(_ item: ScanItem) -> String? {
        guard let assessment = simulatorAssessment, !assessment.deletionDirectories.isEmpty,
              assessment.failedXcodes.isEmpty else { return "Could not check all installed Xcodes. Rescan before deleting simulator devices." }
        guard let device = assessment.devices[item.displayName.uppercased()] else {
            return "CoreSimulator does not recognize this folder. It cannot be deleted through simctl here."
        }
        return device.state == "Shutdown" ? nil : "Shut down this simulator before deleting it."
    }

    func applyRuntimeInventory(_ runtimes: [CleanupOperations.SimulatorRuntime], associations: [String: Set<CleanupOperations.SimulatorXcode>],
                               unavailable: Bool = false, associationCheckFailed: Bool = false) {
        runtimeInventoryUnavailable = unavailable
        runtimeAssociationCheckFailed = associationCheckFailed || unavailable
        // A failed refresh must not turn previously managed images into ordinary Trash targets.
        guard !unavailable else { applyOSFilter(); refreshAvailableCleanupBytes(); return }
        simulatorRuntimes = excludedFolders.contains("simulatorRuntimes") ? [] : runtimes.filter { !cleanedRuntimes.contains($0.id) }
        runtimeAssociations = associations
        let paths = runtimes.flatMap(\.managedPaths).compactMap { try? FilesystemPath(URL(fileURLWithPath: $0)) }
        managedRuntimePaths = cleanedRuntimes.isEmpty ? paths : Array(Set(managedRuntimePaths + paths))
        selectedRuntimes.formIntersection(runtimes.map(\.id))
        applyOSFilter()
        refreshAvailableCleanupBytes()
    }

    func runtimeSelectionUnavailableReason(_ runtime: CleanupOperations.SimulatorRuntime) -> String? {
        if isScanning || isShowingCachedResults { return "Wait for the scan to finish." }
        if runtimeInventoryUnavailable || runtimeAssociationCheckFailed { return "Could not check runtime associations. Rescan before removing runtimes." }
        guard runtime.deletable == true, ["Ready", "Unusable"].contains(runtime.state) else { return "CoreSimulator does not currently allow removal of this runtime." }
        if simulatorAssessment?.devices.values.contains(where: { $0.runtime == runtime.runtimeIdentifier && $0.state != "Shutdown" }) == true {
            return "Shut down devices using this OS before removing its runtime."
        }
        return nil
    }

    func runtimeBlockingReason(_ runtime: CleanupOperations.SimulatorRuntime) -> String? {
        if let reason = runtimeSelectionUnavailableReason(runtime) { return reason }
        if activityUnavailable { return "Could not check running tools. Rescan before cleanup." }
        if let appState, !appState.installationTasks.isEmpty || !appState.runtimeTasks.isEmpty { return "Wait for Xcodes downloads and installations to finish." }
        if !activeTools.isDisjoint(with: ["simulator", "xcodebuild", "swift", "swift-frontend"]) { return "Quit Simulator and stop builds before removing OS runtimes." }
        return nil
    }

    func setRuntimeSelected(_ runtime: CleanupOperations.SimulatorRuntime, selected: Bool) {
        guard !isCleaning else { return }
        if selected {
            guard runtimeSelectionUnavailableReason(runtime) == nil else { return }
            selectedRuntimes.insert(runtime.id)
        } else { selectedRuntimes.remove(runtime.id) }
    }

    func toggleRuntimeSelection() {
        guard !isCleaning, !isScanning else { return }
        let eligible = Set(visibleRuntimes.filter { runtimeSelectionUnavailableReason($0) == nil }.map(\.id))
        if eligible.isSubset(of: selectedRuntimes) { selectedRuntimes.subtract(eligible) }
        else { selectedRuntimes.formUnion(eligible) }
    }

    func applySimulatorInventory(names: [String: String]) {
        simulatorNames.merge(names) { _, current in current }
    }

    func resolveUnknownSimulatorNames() {
        guard simulatorNamesTask == nil else { return }
        let candidates = sections.flatMap(\.items).filter { item in
            guard let id = UUID(uuidString: item.displayName)?.uuidString else { return false }
            return savedSimulatorDetails[id] == nil && simulatorAssessment?.devices[id] == nil && !attemptedSimulatorNames.contains(id) && classification(for: item) == .simulatorDevice
        }
        guard !candidates.isEmpty else { return }
        attemptedSimulatorNames.formUnion(candidates.compactMap { UUID(uuidString: $0.displayName)?.uuidString })
        let token = generation
        simulatorNamesTask = Task { [weak self] in
            let details = await CleanupOperations.localSimulatorDetails(candidates)
            guard let self, self.generation == token, !Task.isCancelled else { return }
            // simctl is authoritative if its response arrived while local metadata was read.
            self.savedSimulatorDetails.merge(details) { _, current in current }
            self.simulatorNames.merge(details.mapValues(\.name)) { current, _ in current }
            self.applyOSFilter()
            self.simulatorNamesTask = nil
            self.resolveUnknownSimulatorNames()
        }
    }

    static func makeProtectedPaths() -> Set<FilesystemPath> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = ["/", "/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/Applications", "/Users", home.path,
                     home.appendingPathComponent("Library").path, Path.xcodesApplicationSupport.string,
                     home.appendingPathComponent("Library/Developer/CoreSimulator").path]
        return Set(paths.compactMap { try? FilesystemPath(URL(fileURLWithPath: $0)) })
    }
}
