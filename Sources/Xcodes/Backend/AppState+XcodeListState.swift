import AppKit
import Foundation
import Path
import Version
import XcodesKit

extension AppState {
    func updateAllXcodes(
        availableXcodes: [AvailableXcode],
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String?
    ) {
        let adjustedAvailableXcodes = adjustedAvailableXcodes(
            availableXcodes: availableXcodes,
            installedXcodes: installedXcodes
        )
        var newAllXcodes = mappedXcodes(
            adjustedAvailableXcodes: adjustedAvailableXcodes,
            availableXcodes: availableXcodes,
            installedXcodes: installedXcodes,
            selectedXcodePath: selectedXcodePath
        )

        appendMissingInstalledXcodes(
            installedXcodes: installedXcodes,
            selectedXcodePath: selectedXcodePath,
            allXcodes: &newAllXcodes
        )

        allXcodes = newAllXcodes.sorted { $0.version > $1.version }
    }

    private func adjustedAvailableXcodes(
        availableXcodes: [AvailableXcode],
        installedXcodes: [InstalledXcode]
    ) -> [AvailableXcode] {
        guard dataSource == .apple else { return availableXcodes }

        var adjustedAvailableXcodes = availableXcodes
        for installedXcode in installedXcodes {
            adjustAvailableXcode(installedXcode, in: &adjustedAvailableXcodes)
        }
        return adjustedAvailableXcodes
    }

    private func adjustAvailableXcode(_ installedXcode: InstalledXcode, in xcodes: inout [AvailableXcode]) {
        if let index = xcodes.map(\.version).firstIndex(
            where: { $0.buildMetadataIdentifiers == installedXcode.version.buildMetadataIdentifiers }
        ) {
            xcodes[index].xcodeID = installedXcode.xcodeID
        } else if let index = xcodes.firstIndex(where: { availableXcode in
            availableXcode.version.isEquivalent(to: installedXcode.version) &&
                availableXcode.version.buildMetadataIdentifiers.isEmpty
        }) {
            xcodes[index].xcodeID = installedXcode.xcodeID
        }
    }

    private func mappedXcodes(
        adjustedAvailableXcodes: [AvailableXcode],
        availableXcodes: [AvailableXcode],
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String?
    ) -> [Xcode] {
        adjustedAvailableXcodes
            .filter { shouldIncludeAvailableXcode($0, availableXcodes: availableXcodes) }
            .map { availableXcode in
                xcode(
                    from: availableXcode,
                    availableXcodes: availableXcodes,
                    installedXcodes: installedXcodes,
                    selectedXcodePath: selectedXcodePath
                )
            }
    }

    private func shouldIncludeAvailableXcode(
        _ availableXcode: AvailableXcode,
        availableXcodes: [AvailableXcode]
    ) -> Bool {
        guard !availableXcode.version.buildMetadataIdentifiers.isEmpty else { return true }

        let availableIdenticalBuilds = availableXcodes
            .filter { $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers }

        return availableIdenticalBuilds.count == 1 ||
            availableIdenticalBuilds.count > 1 &&
            (availableXcode.version.prereleaseIdentifiers.isEmpty || availableXcode.architectures?.count ?? 0 != 0)
    }

    private func xcode(
        from availableXcode: AvailableXcode,
        availableXcodes: [AvailableXcode],
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String?
    ) -> Xcode {
        let installedXcode = installedXcodes.first {
            availableXcode.version.isEquivalent(to: $0.version)
        }
        let existingXcodeInstallState = allXcodes
            .first { $0.id == availableXcode.xcodeID && $0.installState.installing }?.installState
        let defaultXcodeInstallState: XcodeInstallState = installedXcode
            .map { .installed($0.path) } ?? .notInstalled

        let selected = installedXcode
            .map { selectedXcodePath?.hasPrefix($0.path.string) == true } ?? false

        return Xcode(
            version: availableXcode.version,
            identicalBuilds: identicalBuilds(for: availableXcode, availableXcodes: availableXcodes),
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

    private func identicalBuilds(for availableXcode: AvailableXcode, availableXcodes: [AvailableXcode]) -> [XcodeID] {
        let prereleaseIdenticalBuilds = availableXcodes
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

    private func appendMissingInstalledXcodes(
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String?,
        allXcodes: inout [Xcode]
    ) {
        for installedXcode in installedXcodes
            where !allXcodes.contains(where: { xcode in xcode.version.isEquivalent(to: installedXcode.version) }) {
            allXcodes.append(
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
