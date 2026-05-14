import AppKit
import Foundation
import Path
import Version
import RhodonKit

extension AppState {
    func updateAllRhodon(
        availableRhodon: [AvailableXcode],
        installedRhodon: [InstalledXcode],
        selectedXcodePath: String?
    ) {
        let adjustedAvailableRhodon = adjustedAvailableRhodon(
            availableRhodon: availableRhodon,
            installedRhodon: installedRhodon
        )
        var newAllRhodon = mappedRhodon(
            adjustedAvailableRhodon: adjustedAvailableRhodon,
            availableRhodon: availableRhodon,
            installedRhodon: installedRhodon,
            selectedXcodePath: selectedXcodePath
        )

        appendMissingInstalledRhodon(
            installedRhodon: installedRhodon,
            selectedXcodePath: selectedXcodePath,
            allRhodon: &newAllRhodon
        )

        allRhodon = newAllRhodon.sorted { $0.version > $1.version }
    }

    private func adjustedAvailableRhodon(
        availableRhodon: [AvailableXcode],
        installedRhodon: [InstalledXcode]
    ) -> [AvailableXcode] {
        guard dataSource == .apple else { return availableRhodon }

        var adjustedAvailableRhodon = availableRhodon
        for installedXcode in installedRhodon {
            adjustAvailableXcode(installedXcode, in: &adjustedAvailableRhodon)
        }
        return adjustedAvailableRhodon
    }

    private func adjustAvailableXcode(_ installedXcode: InstalledXcode, in rhodon: inout [AvailableXcode]) {
        if let index = rhodon.map(\.version).firstIndex(
            where: { $0.buildMetadataIdentifiers == installedXcode.version.buildMetadataIdentifiers }
        ) {
            rhodon[index].xcodeID = installedXcode.xcodeID
        } else if let index = rhodon.firstIndex(where: { availableXcode in
            availableXcode.version.isEquivalent(to: installedXcode.version) &&
                availableXcode.version.buildMetadataIdentifiers.isEmpty
        }) {
            rhodon[index].xcodeID = installedXcode.xcodeID
        }
    }

    private func mappedRhodon(
        adjustedAvailableRhodon: [AvailableXcode],
        availableRhodon: [AvailableXcode],
        installedRhodon: [InstalledXcode],
        selectedXcodePath: String?
    ) -> [Xcode] {
        adjustedAvailableRhodon
            .filter { shouldIncludeAvailableXcode($0, availableRhodon: availableRhodon) }
            .map { availableXcode in
                xcode(
                    from: availableXcode,
                    availableRhodon: availableRhodon,
                    installedRhodon: installedRhodon,
                    selectedXcodePath: selectedXcodePath
                )
            }
    }

    private func shouldIncludeAvailableXcode(
        _ availableXcode: AvailableXcode,
        availableRhodon: [AvailableXcode]
    ) -> Bool {
        guard !availableXcode.version.buildMetadataIdentifiers.isEmpty else { return true }

        let availableIdenticalBuilds = availableRhodon
            .filter { $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers }

        return availableIdenticalBuilds.count == 1 ||
            availableIdenticalBuilds.count > 1 &&
            (availableXcode.version.prereleaseIdentifiers.isEmpty || availableXcode.architectures?.count ?? 0 != 0)
    }

    private func xcode(
        from availableXcode: AvailableXcode,
        availableRhodon: [AvailableXcode],
        installedRhodon: [InstalledXcode],
        selectedXcodePath: String?
    ) -> Xcode {
        let installedXcode = installedRhodon.first {
            availableXcode.version.isEquivalent(to: $0.version)
        }
        let existingXcodeInstallState = allRhodon
            .first { $0.id == availableXcode.xcodeID && $0.installState.installing }?.installState
        let defaultXcodeInstallState: XcodeInstallState = installedXcode
            .map { .installed($0.path) } ?? .notInstalled

        let selected = installedXcode
            .map { selectedXcodePath?.hasPrefix($0.path.string) == true } ?? false

        return Xcode(
            version: availableXcode.version,
            identicalBuilds: identicalBuilds(for: availableXcode, availableRhodon: availableRhodon),
            installState: existingXcodeInstallState ?? defaultXcodeInstallState,
            selected: selected,
            icon: (installedXcode?.path.string).map(NSWorkspace.shared.icon(forFile:)),
            requiredMacOSVersion: availableXcode.requiredMacOSVersion,
            releaseNotesURL: availableXcode.releaseNotesURL,
            releaseDate: availableXcode.releaseDate,
            sdks: availableXcode.sdks,
            compilers: availableXcode.compilers,
            downloadFileSize: availableXcode.fileSize,
            architectures: availableXcode.architectures
        )
    }

    private func identicalBuilds(for availableXcode: AvailableXcode, availableRhodon: [AvailableXcode]) -> [XcodeID] {
        let prereleaseIdenticalBuilds = availableRhodon
            .filter {
                $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers &&
                    !$0.version.prereleaseIdentifiers.isEmpty &&
                    !$0.version.buildMetadataIdentifiers.isEmpty
            }

        if !prereleaseIdenticalBuilds.isEmpty, availableXcode.version.prereleaseIdentifiers.isEmpty {
            return [availableXcode.xcodeID] + prereleaseIdenticalBuilds.map(\.xcodeID)
        } else {
            return []
        }
    }

    private func appendMissingInstalledRhodon(
        installedRhodon: [InstalledXcode],
        selectedXcodePath: String?,
        allRhodon: inout [Xcode]
    ) {
        for installedXcode in installedRhodon
            where !allRhodon.contains(where: { xcode in xcode.version.isEquivalent(to: installedXcode.version) }) {
            allRhodon.append(
                Xcode(
                    version: installedXcode.version,
                    installState: .installed(installedXcode.path),
                    selected: selectedXcodePath?.hasPrefix(installedXcode.path.string) == true,
                    icon: NSWorkspace.shared.icon(forFile: installedXcode.path.string)
                )
            )
        }
    }
}
