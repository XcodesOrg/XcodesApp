import Foundation
import XcodesKit

enum XcodesAlert: Identifiable {
    case cancelInstall(xcode: Xcode)
    case cancelRuntimeInstall(runtime: DownloadableRuntime)
    case privilegedHelper
    case generic(title: String, message: String)
    case checkMinSupportedVersion(xcode: AvailableXcode, macOS: String)
    case unauthenticated

    var id: Int {
        switch self {
        case .cancelInstall: return 1
        case .privilegedHelper: return 2
        case .generic: return 3
        case .checkMinSupportedVersion: return 4
        case .cancelRuntimeInstall: return 5
        case .unauthenticated: return 6
        }
    }
}

// Splitting out alerts that are shown on the preference screen as by default we are showing on the MainWindow()
// and users awkwardly switch screens, sometimes losing the preference screen
enum XcodesPreferencesAlert: Identifiable {
    case deletePlatform(runtime: DownloadableRuntime)
    case generic(title: String, message: String)
    
    var id: Int {
        switch self {
        case .deletePlatform: return 1
        case .generic: return 2
        }
    }
}
