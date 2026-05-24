import Foundation

public extension OperatingSystemVersion {
    func versionString() -> String {
        "\(majorVersion).\(minorVersion).\(patchVersion)"
    }
}
