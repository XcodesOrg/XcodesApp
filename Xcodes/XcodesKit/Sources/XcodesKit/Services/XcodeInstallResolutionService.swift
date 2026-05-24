import Foundation
@preconcurrency import Path
@preconcurrency import Version

public enum XcodeInstallRequest: Equatable, Sendable {
    case latest
    case latestPrerelease
    case availableXcode(AvailableXcode)
    case version(String)
    case path(versionString: String, path: Path)
}

public enum XcodeInstallResolution: Equatable, Sendable {
    case download(version: Version, resolvedXcode: AvailableXcode?)
    case localArchive(AvailableXcode, URL)
}

public enum XcodeInstallResolutionError: LocalizedError, Equatable, Sendable {
    case invalidVersion(String)
    case noReleaseVersionAvailable
    case noPrereleaseVersionAvailable
    case versionAlreadyInstalled(InstalledXcode)

    public var errorDescription: String? {
        switch self {
        case let .invalidVersion(version):
            return "\(version) is not a valid version number."
        case .noReleaseVersionAvailable:
            return "No release versions available."
        case .noPrereleaseVersionAvailable:
            return "No prerelease versions available."
        case let .versionAlreadyInstalled(installedXcode):
            return "\(installedXcode.version.appleDescription) is already installed at \(installedXcode.path)"
        }
    }
}

public struct XcodeInstallResolutionService: Sendable {
    private let versionFile: XcodeVersionFileService

    public init(versionFile: XcodeVersionFileService = XcodeVersionFileService()) {
        self.versionFile = versionFile
    }

    public func resolve(
        _ request: XcodeInstallRequest,
        availableXcodes: [AvailableXcode],
        installedXcodes: [InstalledXcode],
        willInstall: Bool,
        versionFileDirectory: Path = Path(.cwd)
    ) throws -> XcodeInstallResolution {
        switch request {
        case .latest:
            guard let xcode = latestRelease(in: availableXcodes) else {
                throw XcodeInstallResolutionError.noReleaseVersionAvailable
            }
            try ensureNotInstalled(xcode.version, installedXcodes: installedXcodes, willInstall: willInstall)
            return .download(version: xcode.version, resolvedXcode: xcode)

        case .latestPrerelease:
            guard let xcode = latestPrerelease(in: availableXcodes) else {
                throw XcodeInstallResolutionError.noPrereleaseVersionAvailable
            }
            try ensureNotInstalled(xcode.version, installedXcodes: installedXcodes, willInstall: willInstall)
            return .download(version: xcode.version, resolvedXcode: xcode)

        case let .availableXcode(xcode):
            try ensureNotInstalled(xcode.version, installedXcodes: installedXcodes, willInstall: willInstall)
            return .download(version: xcode.version, resolvedXcode: xcode)

        case let .version(versionString):
            let version = try parsedVersion(versionString, versionFileDirectory: versionFileDirectory)
            try ensureNotInstalled(version, installedXcodes: installedXcodes, willInstall: willInstall)
            return .download(version: version, resolvedXcode: nil)

        case let .path(versionString, path):
            let version = try parsedVersion(versionString, versionFileDirectory: versionFileDirectory)
            let xcode = AvailableXcode(
                version: version,
                url: path.url,
                filename: String(path.string.suffix(fromLast: "/")),
                releaseDate: nil
            )
            return .localArchive(xcode, path.url)
        }
    }

    public func latestRelease(in availableXcodes: [AvailableXcode]) -> AvailableXcode? {
        availableXcodes
            .filter(\.version.isNotPrerelease)
            .sorted(\.version)
            .last
    }

    public func latestPrerelease(in availableXcodes: [AvailableXcode]) -> AvailableXcode? {
        availableXcodes
            .filter { $0.version.isPrerelease }
            .filter { $0.releaseDate != nil }
            .sorted { $0.releaseDate! < $1.releaseDate! }
            .last
    }

    private func parsedVersion(
        _ versionString: String,
        versionFileDirectory: Path
    ) throws -> Version {
        if let version = Version(xcodeVersion: versionString) ?? versionFile.version(inDirectory: versionFileDirectory) {
            return version
        }
        throw XcodeInstallResolutionError.invalidVersion(versionString)
    }

    private func ensureNotInstalled(
        _ version: Version,
        installedXcodes: [InstalledXcode],
        willInstall: Bool
    ) throws {
        guard willInstall else { return }
        if let installedXcode = installedXcodes.first(where: { $0.version.isEquivalent(to: version) }) {
            throw XcodeInstallResolutionError.versionAlreadyInstalled(installedXcode)
        }
    }
}
