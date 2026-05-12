import Foundation
import Path
import XcodesKit

enum XcodeInstallState: Equatable, @unchecked Sendable {
    case notInstalled
    case installing(XcodeInstallationStep)
    case installed(Path)

    var notInstalled: Bool {
        switch self {
        case .notInstalled: return true
        default: return false
        }
    }    
    var installing: Bool { 
        switch self {
        case .installing: return true
        default: return false
        }
    }
    var installed: Bool { 
        switch self {
        case .installed: return true
        default: return false
        }
    }
}
