import Darwin
import Foundation
import XcodesCleanupKit

enum CleanupOperationError: Error, LocalizedError {
    case changed, deviceNotStopped, deviceNotRegistered, associationsChanged, runtimeNotDeletable
    var errorDescription: String? {
        switch self {
        case .changed: "The item changed or disappeared since the scan. Rescan before cleanup."
        case .deviceNotStopped: "This simulator is running or changing state. Shut it down before deleting it."
        case .deviceNotRegistered: "CoreSimulator no longer recognizes this device. Rescan before cleanup."
        case .runtimeNotDeletable: "This runtime cannot currently be removed by CoreSimulator."
        case .associationsChanged: "The Xcode association could not be verified or changed after confirmation. Review the updated warning and try again."
        }
    }
}

/// Injected file operations remain consistent with Xcodes' existing environment and test doubles.
enum CleanupOperations {
    static func validate(_ item: ScanItem) async throws {
        try await onWorker { try validateIdentity(item) }
    }

    static func trash(_ item: ScanItem, files: Files) async throws {
        try await onWorker {
            try validateIdentity(item)
            _ = try files.trashItem(at: item.path.url)
        }
    }

    static func validateIdentity(_ item: ScanItem) throws {
        var metadata = stat()
        let status = item.path.url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return Int32(-1) }
            return lstat(pointer, &metadata)
        }
        guard status == 0, metadata.st_ino == item.identity.inode,
              UInt64(UInt32(bitPattern: metadata.st_dev)) == item.identity.device else { throw CleanupOperationError.changed }
    }

    struct SimulatorRuntime: Sendable, Codable, Identifiable, Equatable {
        let identifier: String
        let runtimeIdentifier: String
        let build: String
        let path: String
        let parentImagePath: String?
        let runtimeBundlePath: String?
        let sizeBytes: UInt64
        let deletable: Bool?
        let state: String
        var id: String { identifier.uppercased() }
        var name: String { simulatorRuntimeName(runtimeIdentifier) }
        var managedPaths: [String] { [path, parentImagePath, runtimeBundlePath].compactMap { $0 } }
    }

    static func simulatorRuntimes() async throws -> [SimulatorRuntime] {
        let output = try await runSimctl(["runtime", "list", "--json"])
        return try decodeSimulatorRuntimes(Data(output.out.utf8))
    }

    static func decodeSimulatorRuntimes(_ data: Data) throws -> [SimulatorRuntime] {
        try JSONDecoder().decode([String: SimulatorRuntime].self, from: data).values
            .filter { UUID(uuidString: $0.identifier) != nil && $0.path.hasPrefix("/") }
            .sorted { $0.sizeBytes == $1.sizeBytes ? $0.id < $1.id : $0.sizeBytes > $1.sizeBytes }
    }

    static func runtimeMatches(developerDirectory: String) async throws -> Set<String> {
        let output = try await runSimctl(["runtime", "match", "list", "--json"], developerDirectory: developerDirectory)
        struct Match: Decodable { let chosenRuntimeBuild: String? }
        return Set(try JSONDecoder().decode([String: Match].self, from: Data(output.out.utf8)).values.compactMap(\.chosenRuntimeBuild))
    }

    static func validateRuntimeDeletion(_ runtime: SimulatorRuntime, fresh: [SimulatorRuntime], devices: SimulatorInventory) throws {
        guard let current = fresh.first(where: { $0.id == runtime.id }), current.path == runtime.path,
              current.build == runtime.build, current.runtimeIdentifier == runtime.runtimeIdentifier,
              current.sizeBytes == runtime.sizeBytes else { throw CleanupOperationError.changed }
        guard current.deletable == true, ["Ready", "Unusable"].contains(current.state) else { throw CleanupOperationError.runtimeNotDeletable }
        guard !devices.devices.values.contains(where: { $0.runtime == runtime.runtimeIdentifier && $0.state != "Shutdown" }) else {
            throw CleanupOperationError.deviceNotStopped
        }
    }

    struct SimulatorDevice: Sendable, Codable, Equatable {
        let id: String
        let name: String
        let runtime: String
        var model: String? = nil
        var runtimeName: String? = nil
        let isAvailable: Bool?
        let state: String
    }

    struct SimulatorInventory: Sendable {
        var devices: [String: SimulatorDevice]
    }

    struct SimulatorXcode: Sendable, Hashable {
        let developerDirectory: String
        let name: String
        let selected: Bool
    }

    struct SimulatorAssessment: Sendable {
        var devices: [String: SimulatorDevice] = [:]
        var associations: [String: Set<SimulatorXcode>] = [:]
        var failedXcodes: [SimulatorXcode] = []
        var deletionDirectories: [String: String] = [:]

        mutating func include(_ inventory: SimulatorInventory, xcode: SimulatorXcode) {
            for (id, device) in inventory.devices {
                // A running/transitional state reported by any Xcode wins over Shutdown.
                if devices[id] == nil || device.state != "Shutdown" { devices[id] = device }
                deletionDirectories[id] = deletionDirectories[id] ?? xcode.developerDirectory
                if device.isAvailable == true { associations[id, default: []].insert(xcode) }
            }
        }
    }

    static func simulatorDevices(developerDirectory: String? = nil) async throws -> SimulatorInventory {
        let output = try await runSimctl(["list", "--json"], developerDirectory: developerDirectory)
        return try decodeSimulatorDevices(Data(output.out.utf8))
    }

    static func assessSimulators(xcodes: [SimulatorXcode]) async -> SimulatorAssessment {
        var assessment = SimulatorAssessment()
        // Sequential queries bound CoreSimulator work and do not change xcode-select.
        for xcode in xcodes {
            guard !Task.isCancelled else { return assessment }
            do { assessment.include(try await simulatorDevices(developerDirectory: xcode.developerDirectory), xcode: xcode) }
            catch { assessment.failedXcodes.append(xcode) }
        }
        return assessment
    }

    static func runSimctl(_ arguments: [String], developerDirectory: String? = nil) async throws -> ProcessOutput {
        if let developerDirectory {
            return try await Process.runAsync(URL(fileURLWithPath: "/usr/bin/env"),
                ["DEVELOPER_DIR=" + developerDirectory, "/usr/bin/xcrun", "simctl"] + arguments)
        }
        return try await Process.runAsync(URL(fileURLWithPath: "/usr/bin/xcrun"), ["simctl"] + arguments)
    }

    static func decodeSimulatorDevices(_ data: Data) throws -> SimulatorInventory {
        struct Response: Decodable {
            let devices: [String: [Device]]
            let devicetypes: [DeviceType]?
            let runtimes: [Runtime]?
        }
        struct DeviceType: Decodable { let identifier: String; let name: String }
        struct Runtime: Decodable { let identifier: String; let name: String }
        struct Device: Decodable { let udid: String; let name: String; let isAvailable: Bool?; let state: String; let deviceTypeIdentifier: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let models = Dictionary((response.devicetypes ?? []).map { ($0.identifier, $0.name) }, uniquingKeysWith: { first, _ in first })
        let runtimeNames = Dictionary((response.runtimes ?? []).map { ($0.identifier, $0.name) }, uniquingKeysWith: { first, _ in first })
        var devices: [String: SimulatorDevice] = [:]
        for (runtime, entries) in response.devices {
            for device in entries {
                guard let id = UUID(uuidString: device.udid)?.uuidString, !device.name.isEmpty else { continue }
                devices[id] = SimulatorDevice(id: id, name: device.name, runtime: runtime,
                    model: device.deviceTypeIdentifier.map { models[$0] ?? simulatorModelName($0) },
                    runtimeName: runtimeNames[runtime] ?? simulatorRuntimeName(runtime), isAvailable: device.isAvailable, state: device.state)
            }
        }
        return SimulatorInventory(devices: devices)
    }

    static func simulatorRuntimeName(_ identifier: String) -> String {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        guard identifier.hasPrefix(prefix) else { return "Unknown OS version" }
        let parts = identifier.dropFirst(prefix.count).split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return "Unknown OS version" }
        return String(platform == "xrOS" ? "visionOS" : platform) + " " + parts.dropFirst().joined(separator: ".")
    }

    static func simulatorModelName(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "com.apple.CoreSimulator.SimDeviceType.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    static func validateSimulatorAssociations(current: Set<SimulatorXcode>, confirmed: Set<SimulatorXcode>) throws {
        guard current.isSubset(of: confirmed) else { throw CleanupOperationError.associationsChanged }
    }

    static func validateSimulatorDeletion(id: String, inventory: SimulatorInventory) throws {
        guard let device = inventory.devices[id.uppercased()] else { throw CleanupOperationError.deviceNotRegistered }
        guard device.state == "Shutdown" else { throw CleanupOperationError.deviceNotStopped }
    }

    static func validateSimulatorRefresh(id: String, assessed: SimulatorInventory, fresh: SimulatorInventory) throws {
        try validateSimulatorDeletion(id: id, inventory: fresh)
        guard fresh.devices[id.uppercased()]?.isAvailable == assessed.devices[id.uppercased()]?.isAvailable else {
            throw CleanupOperationError.associationsChanged
        }
    }

    /// Saved metadata supplies labels only; fresh simctl inventory authorizes deletion.
    static func localSimulatorDetails(_ items: [ScanItem]) async -> [String: SimulatorDevice] {
        (try? await onWorker {
            var devices: [String: SimulatorDevice] = [:]
            for item in items {
                guard item.kind == .directory, let id = UUID(uuidString: item.displayName)?.uuidString,
                      let data = try? Data(contentsOf: item.path.url.appendingPathComponent("device.plist")),
                      let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let name = metadata["name"] as? String, !name.isEmpty else { continue }
                let runtime = metadata["runtime"] as? String ?? ""
                devices[id] = SimulatorDevice(id: id, name: name, runtime: runtime,
                    model: (metadata["deviceType"] as? String).map(simulatorModelName),
                    runtimeName: simulatorRuntimeName(runtime), isAvailable: nil, state: "Unknown")
            }
            // Saved state must never authorize deletion; only a fresh simctl inventory can.
            return devices
        }) ?? [:]
    }

    private static func onWorker<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
