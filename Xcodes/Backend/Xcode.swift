import AppKit
import Foundation
import Version
import Path
import XcodesKit

public struct XcodeID: Codable, Hashable, Identifiable {
    public let version: Version
    public let architectures: [Architecture]?
    
    public var id: String {
        let architectures = architectures?.map { $0.rawValue}.joined() ?? ""
        return version.description + architectures
    }
    
    public init(version: Version, architectures: [Architecture]? = nil) {
        self.version = version
        self.architectures = architectures
    }
}

struct Xcode: Identifiable, CustomStringConvertible {
    var version: Version {
        return id.version
    }
    /// Other Xcode versions that have the same build identifier
    let identicalBuilds: [XcodeID]
    var installState: XcodeInstallState
    let selected: Bool
    let icon: NSImage?
    let requiredMacOSVersion: String?
    let releaseNotesURL: URL?
    let releaseDate: Date?
    let sdks: SDKs?
    let compilers: Compilers?
    let downloadFileSize: Int64?
    let architectures: [Architecture]?
    let id: XcodeID
    
    init(
        version: Version,
        identicalBuilds: [XcodeID] = [],
        installState: XcodeInstallState,
        selected: Bool,
        icon: NSImage?,
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
        self.icon = icon
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.releaseDate = releaseDate
        self.sdks = sdks
        self.compilers = compilers
        self.downloadFileSize = downloadFileSize
        self.architectures = architectures
        self.id = XcodeID(version: version, architectures: architectures)
    }
    
    var description: String {
        version.appleDescription
    }
    
    var downloadFileSizeString: String? {
        if let downloadFileSize = downloadFileSize {
            return ByteCountFormatter.string(fromByteCount: downloadFileSize, countStyle: .file)
        } else {
            return nil
        }
    }
    
    var installedPath: Path? {
        switch installState {
            case .installed(let path):
                return path
            default:
                return nil
        }
    }

}

struct XcodeMinorVersionGroup: Identifiable {
    let majorVersion: Int
    let minorVersion: Int
    let versions: [Xcode]
    var isExpanded: Bool = false

    var id: String {
        "\(majorVersion).\(minorVersion)"
    }

    var latestRelease: Xcode? {
        versions
            .filter { $0.version.isNotPrerelease }
            .sorted { $0.version < $1.version }
            .last
    }

    var displayName: String {
        "\(majorVersion).\(minorVersion)"
    }

    var hasInstalled: Bool {
        versions.contains { $0.installState.installed }
    }

    var hasInstalling: Bool {
        versions.contains { $0.installState.installing }
    }

    var selectedVersion: Xcode? {
        versions.first { $0.selected }
    }
}

struct XcodeMajorVersionGroup: Identifiable {
    let majorVersion: Int
    let minorVersionGroups: [XcodeMinorVersionGroup]
    var isExpanded: Bool = false

    var id: Int {
        majorVersion
    }

    var versions: [Xcode] {
        minorVersionGroups.flatMap { $0.versions }
    }

    var latestRelease: Xcode? {
        versions
            .filter { $0.version.isNotPrerelease }
            .sorted { $0.version < $1.version }
            .last
    }

    var displayName: String {
        "\(majorVersion)"
    }

    var hasInstalled: Bool {
        minorVersionGroups.contains { $0.hasInstalled }
    }

    var hasInstalling: Bool {
        minorVersionGroups.contains { $0.hasInstalling }
    }

    var selectedVersion: Xcode? {
        minorVersionGroups.compactMap { $0.selectedVersion }.first
    }
}

extension Array where Element == Xcode {
    func groupedByMajorVersion() -> [XcodeMajorVersionGroup] {
        let majorGroups = Dictionary(grouping: self) { $0.version.major }
        return majorGroups.map { majorVersion, xcodes in
            let minorGroups = Dictionary(grouping: xcodes) { $0.version.minor }
            let minorVersionGroups = minorGroups.map { minorVersion, minorXcodes in
                XcodeMinorVersionGroup(
                    majorVersion: majorVersion,
                    minorVersion: minorVersion,
                    versions: minorXcodes.sorted { $0.version > $1.version }
                )
            }.sorted { $0.minorVersion > $1.minorVersion }

            return XcodeMajorVersionGroup(
                majorVersion: majorVersion,
                minorVersionGroups: minorVersionGroups
            )
        }.sorted { $0.majorVersion > $1.majorVersion }
    }
}
