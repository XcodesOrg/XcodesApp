import Foundation
@preconcurrency import Path
@preconcurrency import Version

public struct XcodeListItem: Identifiable, Sendable {
    public var version: Version {
        id.version
    }

    public let identicalBuilds: [XcodeID]
    public let installState: XcodeInstallState
    public let selected: Bool
    public let requiredMacOSVersion: String?
    public let releaseNotesURL: URL?
    public let releaseDate: Date?
    public let sdks: SDKs?
    public let compilers: Compilers?
    public let downloadFileSize: Int64?
    public let architectures: [Architecture]?
    public let id: XcodeID

    public init(
        version: Version,
        identicalBuilds: [XcodeID] = [],
        installState: XcodeInstallState,
        selected: Bool,
        requiredMacOSVersion: String? = nil,
        releaseNotesURL: URL? = nil,
        releaseDate: Date? = nil,
        sdks: SDKs? = nil,
        compilers: Compilers? = nil,
        downloadFileSize: Int64? = nil,
        architectures: [Architecture]? = nil
    ) {
        self.identicalBuilds = identicalBuilds
        self.installState = installState
        self.selected = selected
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.releaseDate = releaseDate
        self.sdks = sdks
        self.compilers = compilers
        self.downloadFileSize = downloadFileSize
        self.architectures = architectures
        self.id = XcodeID(version: version, architectures: architectures)
    }

    public var installedPath: Path? {
        installState.installedPath
    }

    public var downloadFileSizeString: String? {
        downloadFileSize.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
    }
}
