import Foundation
@preconcurrency import Path
@preconcurrency import Version

public enum XcodeSelectionError: LocalizedError, Equatable, Sendable {
    case invalidIndex(min: Int, max: Int, given: String?)

    public var errorDescription: String? {
        switch self {
        case let .invalidIndex(min, max, given):
            return "Not a valid number. Expecting a whole number between \(min)-\(max), but given \(given ?? "nothing")."
        }
    }
}

public enum XcodeSelectionRequest: Equatable, Sendable {
    case alreadySelectedVersion(Version)
    case alreadySelectedPath(String)
    case selectInstalledXcode(InstalledXcode)
    case selectPath(String)
}

public struct XcodeSelectionService: Sendable {
    private let versionFile: XcodeVersionFileService

    public init(versionFile: XcodeVersionFileService = XcodeVersionFileService()) {
        self.versionFile = versionFile
    }

    public func request(
        pathOrVersion: String,
        installedXcodes: [InstalledXcode],
        selectedXcodePath: String,
        versionFileDirectory: Path = Path(.cwd)
    ) -> XcodeSelectionRequest {
        let versionToSelect = pathOrVersion.isEmpty
            ? versionFile.version(inDirectory: versionFileDirectory)
            : Version(xcodeVersion: pathOrVersion)

        if let version = versionToSelect,
           let installedXcode = installedXcodes.first(withVersion: version) {
            let selectedInstalledXcode = XcodeListPresentationService.selectedInstalledXcode(
                in: installedXcodes,
                selectedXcodePath: selectedXcodePath
            )

            if installedXcode.version == selectedInstalledXcode?.version {
                return .alreadySelectedVersion(version)
            }

            return .selectInstalledXcode(installedXcode)
        }

        let pathToSelect = pathOrVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPath = selectedXcodePath.trimmingCharacters(in: .whitespacesAndNewlines)

        if pathToSelect == currentPath {
            return .alreadySelectedPath(pathOrVersion)
        }

        return .selectPath(pathToSelect)
    }

    public func installedXcode(
        fromSelection selection: String?,
        installedXcodes: [InstalledXcode]
    ) throws -> InstalledXcode {
        let sortedInstalledXcodes = installedXcodes.sorted { $0.version < $1.version }

        guard
            let selection,
            let selectionNumber = Int(selection),
            sortedInstalledXcodes.indices.contains(selectionNumber - 1)
        else {
            throw XcodeSelectionError.invalidIndex(min: 1, max: sortedInstalledXcodes.count, given: selection)
        }

        return sortedInstalledXcodes[selectionNumber - 1]
    }
}
