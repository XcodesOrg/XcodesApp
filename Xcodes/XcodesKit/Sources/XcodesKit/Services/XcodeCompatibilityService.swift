import Foundation

public enum XcodeCompatibilityStatus: Equatable, Sendable {
    case supported
    case unsupported(requiredMacOSVersion: String, currentMacOSVersion: String)

    public var isSupported: Bool {
        switch self {
        case .supported:
            true
        case .unsupported:
            false
        }
    }

    public var isUnsupported: Bool {
        !isSupported
    }
}

public struct XcodeCompatibilityService: Sendable {
    public init() {}

    public func status(
        for xcode: AvailableXcode,
        currentOSVersion: OperatingSystemVersion
    ) -> XcodeCompatibilityStatus {
        status(
            requiredMacOSVersion: xcode.requiredMacOSVersion,
            currentOSVersion: currentOSVersion
        )
    }

    public func status(
        requiredMacOSVersion: String?,
        currentOSVersion: OperatingSystemVersion
    ) -> XcodeCompatibilityStatus {
        guard let requiredMacOSVersion else {
            return .supported
        }

        let requiredVersion = operatingSystemVersion(from: requiredMacOSVersion)
        if currentOSVersion >= requiredVersion {
            return .supported
        }

        return .unsupported(
            requiredMacOSVersion: requiredMacOSVersion,
            currentMacOSVersion: currentOSVersion.versionString()
        )
    }

    public func isSupported(
        requiredMacOSVersion: String?,
        currentOSVersion: OperatingSystemVersion
    ) -> Bool {
        status(
            requiredMacOSVersion: requiredMacOSVersion,
            currentOSVersion: currentOSVersion
        ).isSupported
    }

    public func isUnsupported(
        requiredMacOSVersion: String?,
        currentOSVersion: OperatingSystemVersion
    ) -> Bool {
        !isSupported(
            requiredMacOSVersion: requiredMacOSVersion,
            currentOSVersion: currentOSVersion
        )
    }

    public func operatingSystemVersion(from versionString: String) -> OperatingSystemVersion {
        let components = versionString
            .components(separatedBy: ".")
            .compactMap { Int($0) }

        return OperatingSystemVersion(
            majorVersion: components.count > 0 ? components[0] : 0,
            minorVersion: components.count > 1 ? components[1] : 0,
            patchVersion: components.count > 2 ? components[2] : 0
        )
    }
}

private extension OperatingSystemVersion {
    static func >= (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        if lhs.majorVersion != rhs.majorVersion {
            return lhs.majorVersion > rhs.majorVersion
        }

        if lhs.minorVersion != rhs.minorVersion {
            return lhs.minorVersion > rhs.minorVersion
        }

        return lhs.patchVersion >= rhs.patchVersion
    }
}
