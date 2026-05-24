import Foundation
@preconcurrency import Path
@preconcurrency import Version

public struct XcodeListPresentationService: Sendable {
    public struct AvailableRow: Equatable, Sendable {
        public let version: Version
        public let versionDescription: String
        public let isInstalled: Bool
        public let isSelected: Bool
    }

    public struct InstalledRow: Equatable, Sendable {
        public let version: Version
        public let versionDescription: String
        public let path: Path
        public let isSelected: Bool
    }

    public init() {}

    public func availableRows(
        availableXcodes: [AvailableXcode],
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String?,
        dataSource: XcodeListDataSource,
        architectures: [Architecture] = []
    ) -> [AvailableRow] {
        struct ReleasedVersion {
            let version: Version
            let releaseDate: Date?
        }

        let adjustedAvailableXcodes = (dataSource == .apple
            ? XcodeListComposer.adjustingAvailableXcodesForInstalledBuildMetadata(
                availableXcodes,
                installedXcodes: installedXcodes
            )
            : availableXcodes)
            .matchingArchitectures(architectures)

        let adjustedInstalledXcodes = architectures.isEmpty
            ? installedXcodes
            : installedXcodes.filter { $0.xcodeID.architectures?.containsAny(architectures) == true }

        var releasedVersions = adjustedAvailableXcodes.map {
            ReleasedVersion(version: $0.version, releaseDate: $0.releaseDate)
        }

        for installedXcode in adjustedInstalledXcodes {
            if !releasedVersions.contains(where: { $0.version.isEquivalent(to: installedXcode.version) }) {
                releasedVersions.append(ReleasedVersion(version: installedXcode.version, releaseDate: nil))
            } else if let index = releasedVersions.firstIndex(where: {
                $0.version.isEquivalent(to: installedXcode.version) &&
                    $0.version.buildMetadataIdentifiers.isEmpty
            }) {
                releasedVersions[index] = ReleasedVersion(version: installedXcode.version, releaseDate: nil)
            }
        }

        let selectedInstalledXcode = Self.selectedInstalledXcode(
            in: adjustedInstalledXcodes,
            selectedXcodePath: selectedXcodePath
        )

        return releasedVersions
            .sorted { first, second -> Bool in
                if first.version.isPrerelease,
                   second.version.isPrerelease,
                   let firstDate = first.releaseDate,
                   let secondDate = second.releaseDate {
                    return firstDate < secondDate
                }
                return first.version < second.version
            }
            .map { releasedVersion in
                let installedXcode = adjustedInstalledXcodes.first {
                    releasedVersion.version.isEquivalent(to: $0.version)
                }
                return AvailableRow(
                    version: releasedVersion.version,
                    versionDescription: releasedVersion.version.appleDescriptionWithBuildIdentifier,
                    isInstalled: installedXcode != nil,
                    isSelected: installedXcode?.path == selectedInstalledXcode?.path
                )
            }
    }

    public func installedRows(
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String?
    ) -> [InstalledRow] {
        installedXcodes
            .sorted { $0.version < $1.version }
            .map { installedXcode in
                InstalledRow(
                    version: installedXcode.version,
                    versionDescription: installedXcode.version.appleDescriptionWithBuildIdentifier,
                    path: installedXcode.path,
                    isSelected: selectedXcodePath?.hasPrefix(installedXcode.path.string) == true
                )
            }
    }

    public func installedLines(
        rows: [InstalledRow],
        interactive: Bool,
        selectedMarker: String = "(Selected)"
    ) -> [String] {
        let firstColumns = rows.map { row in
            row.versionDescription + (row.isSelected ? " \(selectedMarker)" : "")
        }
        let maxWidthOfFirstColumn = (firstColumns.map(\.count).max() ?? 0) + 1

        return rows.enumerated().map { index, row in
            let firstColumn = firstColumns[index]
            if interactive {
                let spaceBetweenColumns = maxWidthOfFirstColumn - firstColumn.count
                return firstColumn +
                    String(repeating: " ", count: max(spaceBetweenColumns, 0)) +
                    row.path.string
            } else {
                return "\(firstColumn)\t\(row.path.string)"
            }
        }
    }

    public static func selectedInstalledXcode(
        in installedXcodes: [InstalledXcode],
        selectedXcodePath: String?
    ) -> InstalledXcode? {
        guard let selectedXcodePath else { return nil }
        return installedXcodes.first { selectedXcodePath.hasPrefix($0.path.string) }
    }
}
