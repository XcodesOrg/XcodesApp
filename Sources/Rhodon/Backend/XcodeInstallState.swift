import Foundation
import Path
import RhodonKit

enum XcodeInstallState: Equatable, @unchecked Sendable {
    case notInstalled
    case installing(XcodeInstallationStep)
    case installed(Path)

    var notInstalled: Bool {
        switch self {
        case .notInstalled: true
        default: false
        }
    }

    var installing: Bool {
        switch self {
        case .installing: true
        default: false
        }
    }

    var installed: Bool {
        switch self {
        case .installed: true
        default: false
        }
    }
}
