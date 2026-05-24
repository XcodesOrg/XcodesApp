import Foundation
@preconcurrency import Version

public struct RuntimeListPresentationService: Sendable {
    public struct RuntimeRow: Sendable {
        public let platform: DownloadableRuntime.Platform
        public let betaNumber: Int?
        public let version: String
        public let build: String
        public let kind: InstalledRuntime.Kind?
        public var hasDuplicateVersion: Bool
        public let architectures: [Architecture]?

        public var completeVersion: String {
            makeRuntimeVersion(for: version, betaNumber: betaNumber)
        }

        public var visibleIdentifier: String {
            let architectureDescription = architectures?.map(\.rawValue).joined(separator: "|")
            return platform.shortName + " " + completeVersion + (architectureDescription != nil ? " \(architectureDescription!)" : "")
        }

        fileprivate init(
            platform: DownloadableRuntime.Platform,
            betaNumber: Int?,
            version: String,
            build: String,
            kind: InstalledRuntime.Kind? = nil,
            hasDuplicateVersion: Bool = false,
            architectures: [Architecture]?
        ) {
            self.platform = platform
            self.betaNumber = betaNumber
            self.version = version
            self.build = build
            self.kind = kind
            self.hasDuplicateVersion = hasDuplicateVersion
            self.architectures = architectures
        }
    }

    public init() {}

    public func rows(
        downloadableRuntimes: DownloadableRuntimesResponse,
        installedRuntimes: [InstalledRuntime],
        includeBetas: Bool,
        architectures: [Architecture] = []
    ) -> [(platform: DownloadableRuntime.Platform, runtimes: [RuntimeRow])] {
        rows(
            downloadableRuntimes: downloadableRuntimes.downloadablesWithSDKBuildUpdates(),
            installedRuntimes: installedRuntimes,
            includeBetas: includeBetas,
            sdkToSeedMappings: downloadableRuntimes.sdkToSeedMappings,
            architectures: architectures
        )
    }

    public func rows(
        downloadableRuntimes: [DownloadableRuntime],
        installedRuntimes: [InstalledRuntime],
        includeBetas: Bool,
        sdkToSeedMappings: [SDKToSeedMapping] = [],
        architectures: [Architecture] = []
    ) -> [(platform: DownloadableRuntime.Platform, runtimes: [RuntimeRow])] {
        var unmatchedInstalledRuntimes = installedRuntimes
        var rows: [RuntimeRow] = []

        downloadableRuntimes.matchingArchitectures(architectures).forEach { downloadable in
            let matchingInstalledRuntimes = unmatchedInstalledRuntimes.removeAll {
                $0.build == downloadable.simulatorVersion.buildUpdate
            }

            if matchingInstalledRuntimes.isEmpty {
                rows.append(RuntimeRow(downloadable))
            } else {
                matchingInstalledRuntimes.forEach { installedRuntime in
                    rows.append(RuntimeRow(downloadable, kind: installedRuntime.kind))
                }
            }
        }

        if architectures.isEmpty {
            unmatchedInstalledRuntimes.forEach { installedRuntime in
                let betaNumber = sdkToSeedMappings.first {
                    $0.buildUpdate == installedRuntime.build
                }?.seedNumber
                var row = RuntimeRow(installedRuntime, betaNumber: betaNumber)

                rows.indices.filter { row.visibleIdentifier == rows[$0].visibleIdentifier }.forEach { index in
                    row.hasDuplicateVersion = true
                    rows[index].hasDuplicateVersion = true
                }

                rows.append(row)
            }
        }

        return Dictionary(grouping: rows, by: \.platform)
            .sorted(\.key.order)
            .map { platform, runtimes in
                (
                    platform: platform,
                    runtimes: runtimes
                        .filter { includeBetas || $0.betaNumber == nil || $0.kind != nil }
                        .sorted(by: sortRuntimes)
                )
            }
    }

    public func line(for row: RuntimeRow) -> String {
        var string = row.visibleIdentifier
        if row.hasDuplicateVersion {
            string += " (\(row.build))"
        }
        if let kind = row.kind {
            switch kind {
            case .bundled:
                string += " (Bundled with selected Xcode)"
            case .legacyDownload, .diskImage, .cryptexDiskImage, .patchableCryptexDiskImage:
                string += " (Installed)"
            }
        }
        return string
    }

    private func sortRuntimes(_ first: RuntimeRow, _ second: RuntimeRow) -> Bool {
        let firstVersion = Version(tolerant: first.completeVersion)!
        let secondVersion = Version(tolerant: second.completeVersion)!
        if firstVersion == secondVersion {
            return first.build.compare(second.build, options: .numeric) == .orderedAscending
        }
        return firstVersion < secondVersion
    }
}

public extension DownloadableRuntimesResponse {
    func downloadablesWithSDKBuildUpdates() -> [DownloadableRuntime] {
        downloadables.map { runtime in
            var updatedRuntime = runtime
            let mappings = sdkToSimulatorMappings.filter {
                $0.simulatorBuildUpdate == runtime.simulatorVersion.buildUpdate
            }
            updatedRuntime.sdkBuildUpdate = mappings.map(\.sdkBuildUpdate)
            return updatedRuntime
        }
    }
}

private extension RuntimeListPresentationService.RuntimeRow {
    init(_ runtime: DownloadableRuntime, kind: InstalledRuntime.Kind? = nil) {
        self.init(
            platform: runtime.platform,
            betaNumber: runtime.betaNumber,
            version: runtime.simulatorVersion.version,
            build: runtime.simulatorVersion.buildUpdate,
            kind: kind,
            architectures: runtime.architectures
        )
    }

    init(_ runtime: InstalledRuntime, betaNumber: Int?) {
        self.init(
            platform: runtime.platformIdentifier.asPlatformOS,
            betaNumber: betaNumber,
            version: runtime.version,
            build: runtime.build,
            kind: runtime.kind,
            architectures: runtime.supportedArchitectures
        )
    }
}

private extension Array {
    mutating func removeAll(where predicate: (Element) -> Bool) -> [Element] {
        guard !isEmpty else { return [] }
        var removed: [Element] = []
        self = filter { current in
            let satisfy = predicate(current)
            if satisfy {
                removed.append(current)
            }
            return !satisfy
        }
        return removed
    }

}
