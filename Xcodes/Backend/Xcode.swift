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
    
    public var architectureString: String {
        switch architectures {
        case .some(let architectures):
            if architectures.isAppleSilicon {
                return "Apple Silicon"
            } else {
                return "Universal"
            }
        default: return "Universal"
        }
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
