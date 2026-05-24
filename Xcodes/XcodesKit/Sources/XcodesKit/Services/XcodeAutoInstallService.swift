import Foundation

public enum XcodeAutoInstallDecision: Equatable, Sendable {
    case disabled
    case alreadyInstalled
    case installNewestBeta(XcodeID)
    case installNewestVersion(XcodeID)
    case noNewVersion
}

public struct XcodeAutoInstallService: Sendable {
    public init() {}

    public func decision(
        autoInstallationType: AutoInstallationType,
        xcodes: [XcodeListItem]
    ) -> XcodeAutoInstallDecision {
        guard autoInstallationType != .none else {
            return .disabled
        }

        guard let newestXcode = xcodes.first, newestXcode.installState == .notInstalled else {
            return .alreadyInstalled
        }

        switch autoInstallationType {
        case .none:
            return .disabled
        case .newestBeta:
            return .installNewestBeta(newestXcode.id)
        case .newestVersion:
            if newestXcode.version.isNotPrerelease {
                return .installNewestVersion(newestXcode.id)
            }
            return .noNewVersion
        }
    }
}
