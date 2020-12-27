import Foundation
import Version

struct Xcode: Identifiable, CustomStringConvertible {
    let version: Version
    let installState: XcodeInstallState
    let selected: Bool
    let path: String?
    
    var id: Version { version }
    var installed: Bool { installState == .installed }
    
    var description: String {
        version.xcodeDescription
    }
}

enum XcodeInstallState: Equatable {
    case notInstalled
    case installing(Progress)
    case installed
}
