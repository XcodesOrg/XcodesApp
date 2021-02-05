import AppKit
import Foundation
import Version
import struct XCModel.SDKs
import struct XCModel.Compilers

struct Xcode: Identifiable, CustomStringConvertible {
    let version: Version
    var installState: XcodeInstallState
    let selected: Bool
    let icon: NSImage?
    let requiredMacOSVersion: String?
    let releaseNotesURL: URL?
    let sdks: SDKs?
    let compilers: Compilers?
    let downloadFileSize: Int64?
    
    init(
        version: Version,
        installState: XcodeInstallState,
        selected: Bool,
        icon: NSImage?,
        requiredMacOSVersion: String? = nil,
        releaseNotesURL: URL? = nil,
        sdks: SDKs? = nil,
        compilers: Compilers? = nil,
        downloadFileSize: Int64? = nil
    ) {
        self.version = version
        self.installState = installState
        self.selected = selected
        self.icon = icon
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
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
}
