import Foundation
import Path

enum XcodeInstallState: Equatable {
    case notInstalled
    case installing(InstallationStep)
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
