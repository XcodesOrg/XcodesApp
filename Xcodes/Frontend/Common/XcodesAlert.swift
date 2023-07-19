import Foundation

enum XcodesAlert: Identifiable {
    case cancelInstall(xcode: Xcode)
    case privilegedHelper
    case generic(title: String, message: String)
    case checkMinSupportedVersion(xcode: AvailableXcode, macOS: String)

    var id: Int {
        switch self {
        case .cancelInstall: return 1
        case .privilegedHelper: return 2
        case .generic: return 3
        case .checkMinSupportedVersion: return 4
        }
    }
}
