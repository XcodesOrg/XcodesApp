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
        case .cancelInstall: 1
        case .privilegedHelper: 2
        case .generic: 3
        case .checkMinSupportedVersion: 4
        case .cancelRuntimeInstall: 5
        case .unauthenticated: 6
        }
    }
}

/// Splitting out alerts that are shown on the preference screen as by default we are showing on the MainWindow()
/// and users awkwardly switch screens, sometimes losing the preference screen
enum XcodesPreferencesAlert: Identifiable {
    case deletePlatform(runtime: DownloadableRuntime)
    case generic(title: String, message: String)

    var id: Int {
        switch self {
        case .deletePlatform: 1
        case .generic: 2
        }
    }
}
