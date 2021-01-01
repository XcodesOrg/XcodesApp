import AppKit
import Foundation
import Version
import struct XCModel.SDKs
import struct XCModel.Compilers

struct Xcode: Identifiable, CustomStringConvertible {
    let version: Version
    let installState: XcodeInstallState
    let selected: Bool
    let path: String?
    let icon: NSImage?
    let requiredMacOSVersion: String?
    let releaseNotesURL: URL?
    let sdks: SDKs?
    let compilers: Compilers?
    
    init(
        version: Version,
        installState: XcodeInstallState,
        selected: Bool,
        path: String?,
        icon: NSImage?,
        requiredMacOSVersion: String? = nil,
        releaseNotesURL: URL? = nil,
        sdks: SDKs? = nil,
        compilers: Compilers? = nil
    ) {
        self.version = version
        self.installState = installState
        self.selected = selected
        self.path = path
        self.icon = icon
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.sdks = sdks
        self.compilers = compilers
    }
    
    var id: Version { version }
    var installed: Bool { installState == .installed }
    
    var description: String {
        version.xcodeDescription
    }
}

enum XcodeInstallState: Equatable {
    case notInstalled
    case installing(InstallationStep)
    case installed
}
