import AppKit
import Foundation
import Version
import struct XCModel.SDKs
import struct XCModel.Compilers
import Path

struct Xcode: Identifiable, CustomStringConvertible {
    let version: Version
    /// Other Xcode versions that have the same build identifier
    let identicalBuilds: [Version]
    var installState: XcodeInstallState
    let selected: Bool
    let icon: NSImage?
    let requiredMacOSVersion: String?
    let releaseNotesURL: URL?
    let releaseDate: Date?
    let sdks: SDKs?
    let compilers: Compilers?
    let downloadFileSize: Int64?
    
    init(
        version: Version,
        identicalBuilds: [Version] = [],
        installState: XcodeInstallState,
        selected: Bool,
        icon: NSImage?,
        requiredMacOSVersion: String? = nil,
        releaseNotesURL: URL? = nil,
        releaseDate: Date? = nil,
        sdks: SDKs? = nil,
        compilers: Compilers? = nil,
        downloadFileSize: Int64? = nil
    ) {
        self.version = version
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
    }
    
    var id: Version { version }
    
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
    
    var installPath: Path? {
        switch installState {
            case .installed(let path):
                return path
            default:
                return nil
        }
    }
}
