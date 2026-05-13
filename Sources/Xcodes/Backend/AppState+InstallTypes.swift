import Combine
import Foundation
import Path
import Version

extension AppState {
    func persistOrCleanUpResumeData(at path: Path, for completion: Subscribers.Completion<some Any>) {
        switch completion {
        case .finished:
            try? current.files.removeItem(at: path.url)
        case let .failure(error):
            guard let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            else { return }
            current.files.createFile(atPath: path.string, contents: resumeData)
        }
    }
}

public enum InstallationError: LocalizedError, Equatable {
    case damagedXIP(url: URL)
    case notEnoughFreeSpaceToExpandArchive(archivePath: Path, version: Version)
    case failedToMoveXcodeToApplications
    case failedSecurityAssessment(xcode: InstalledXcode, output: String)
    case codesignVerifyFailed(output: String)
    case unexpectedCodeSigningIdentity(identifier: String, certificateAuthority: [String])
    case unsupportedFileFormat(extension: String)
    case missingSudoerPassword
    case unavailableVersion(Version)
    case noNonPrereleaseVersionAvailable
    case noPrereleaseVersionAvailable
    case missingUsernameOrPassword
    case versionAlreadyInstalled(InstalledXcode)
    case invalidVersion(String)
    case versionNotInstalled(Version)
    case postInstallStepsNotPerformed(version: Version, helperInstallState: HelperInstallState)

    public var errorDescription: String? {
        switch self {
        case let .damagedXIP(url):
            "The archive \"\(url.lastPathComponent)\" is damaged and can't be expanded."
        case let .notEnoughFreeSpaceToExpandArchive(archivePath, version):
            // swiftlint:disable:next line_length
            "The archive \"\(archivePath.basename())\" can’t be expanded because the current volume doesn’t have enough free space.\n\nMake more space available to expand the archive and then install Xcode \(version.appleDescription) again to start installation from where it left off."
        case .failedToMoveXcodeToApplications:
            "Failed to move Xcode to the \(Path.installDirectory.string) directory."
        case let .failedSecurityAssessment(xcode, output):
            // swiftlint:disable:next line_length
            "Xcode \(String(xcode.version)) failed its security assessment with the following output:\n\(output)\nIt remains installed at \(xcode.path.string) if you wish to use it anyways."
        case let .codesignVerifyFailed(output):
            "The downloaded Xcode failed code signing verification with the following output:\n\(output)"
        case let .unexpectedCodeSigningIdentity(identity, certificateAuthority):
            // swiftlint:disable:next line_length
            "The downloaded Xcode doesn't have the expected code signing identity.\nGot:\n\(identity)\n\(String(describing: certificateAuthority))\nExpected:\n\(xcodeTeamIdentifier)\n\(String(describing: xcodeCertificateAuthority))"
        case let .unsupportedFileFormat(fileExtension):
            "Xcodes doesn't (yet) support installing Xcode from the \(fileExtension) file format."
        case .missingSudoerPassword:
            "Missing password. Please try again."
        case let .unavailableVersion(version):
            "Could not find version \(version.appleDescription)."
        case .noNonPrereleaseVersionAvailable:
            "No non-prerelease versions available."
        case .noPrereleaseVersionAvailable:
            "No prerelease versions available."
        case .missingUsernameOrPassword:
            "Missing username or a password. Please try again."
        case let .versionAlreadyInstalled(installedXcode):
            "\(installedXcode.version.appleDescription) is already installed at \(installedXcode.path.string)"
        case let .invalidVersion(version):
            "\(version) is not a valid version number."
        case let .versionNotInstalled(version):
            "\(version.appleDescription) is not installed."
        case let .postInstallStepsNotPerformed(version, helperInstallState):
            switch helperInstallState {
            case .installed:
                // swiftlint:disable:next line_length
                "Installation was completed, but some post-install steps weren't performed automatically. These will be performed when you first launch Xcode \(version.appleDescription)."
            case .notInstalled, .unknown:
                // swiftlint:disable:next line_length
                "Installation was completed, but some post-install steps weren't performed automatically. Xcodes performs these steps with a privileged helper, which appears to not be installed. You can install it from Preferences > Advanced.\n\nThese steps will be performed when you first launch Xcode \(version.appleDescription)."
            }
        }
    }
}

public enum InstallationType {
    case version(AvailableXcode)
}

public enum AutoInstallationType: Int, Identifiable {
    case none = 0
    case newestVersion
    case newestBeta

    public var id: Self {
        self
    }

    public var isAutoInstalling: Bool {
        get {
            self != .none
        }
        set {
            self = newValue ? .newestVersion : .none
        }
    }

    public var isAutoInstallingBeta: Bool {
        get {
            self == .newestBeta
        }
        set {
            self = newValue ? .newestBeta : (isAutoInstalling ? .newestVersion : .none)
        }
    }
}
