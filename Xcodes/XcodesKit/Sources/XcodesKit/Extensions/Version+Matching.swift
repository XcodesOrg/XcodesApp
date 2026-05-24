import Foundation
import Version

public enum XcodeVersionMatcher: Sendable {
    public static func find<XcodeType>(version: Version, in xcodes: [XcodeType], versionKeyPath: KeyPath<XcodeType, Version>) -> XcodeType? {
        if let equivalentXcode = xcodes.first(where: { $0[keyPath: versionKeyPath].isEquivalent(to: version) }) {
            return equivalentXcode
        } else if version.prereleaseIdentifiers.isEmpty && version.buildMetadataIdentifiers.isEmpty,
                  xcodes.filter({ $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) }).count == 1 {
            return xcodes.first(where: { $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) })
        } else {
            return nil
        }
    }
}

public extension Version {
    func isEqualWithoutAllIdentifiers(to other: Version) -> Bool {
        major == other.major &&
        minor == other.minor &&
        patch == other.patch
    }
}
