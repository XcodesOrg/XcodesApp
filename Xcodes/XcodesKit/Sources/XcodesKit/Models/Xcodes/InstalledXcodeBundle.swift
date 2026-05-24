import Foundation
@preconcurrency import Path
@preconcurrency import Version

public struct XcodeBundleInfo: Equatable, Sendable {
    public let path: Path
    public let bundleID: String?
    public let version: Version

    public init?(path: Path, contentsAtPath: @Sendable (String) -> Data?) {
        let infoPlistPath = path.join("Contents").join("Info.plist")
        let versionPlistPath = path.join("Contents").join("version.plist")

        guard
            let infoPlistData = contentsAtPath(infoPlistPath.string),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData),
            let bundleShortVersion = infoPlist.bundleShortVersion,
            let bundleVersion = Version(tolerant: bundleShortVersion),
            let versionPlistData = contentsAtPath(versionPlistPath.string),
            let versionPlist = try? PropertyListDecoder().decode(VersionPlist.self, from: versionPlistData)
        else { return nil }

        var prereleaseIdentifiers = bundleVersion.prereleaseIdentifiers
        if let filenameVersion = Version(path.basename(dropExtension: true).replacingOccurrences(of: "Xcode-", with: "")) {
            prereleaseIdentifiers = filenameVersion.prereleaseIdentifiers
        } else if infoPlist.bundleIconName == "XcodeBeta", !prereleaseIdentifiers.contains("beta") {
            prereleaseIdentifiers = ["beta"]
        }

        self.path = path
        self.bundleID = infoPlist.bundleID
        self.version = Version(
            major: bundleVersion.major,
            minor: bundleVersion.minor,
            patch: bundleVersion.patch,
            prereleaseIdentifiers: prereleaseIdentifiers,
            buildMetadataIdentifiers: [versionPlist.productBuildVersion].compactMap { $0 }
        )
    }
}

public struct InfoPlist: Decodable, Sendable {
    public let bundleID: String?
    public let bundleShortVersion: String?
    public let bundleIconName: String?

    public enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier"
        case bundleShortVersion = "CFBundleShortVersionString"
        case bundleIconName = "CFBundleIconName"
    }
}

public struct VersionPlist: Decodable, Sendable {
    public let productBuildVersion: String

    public enum CodingKeys: String, CodingKey {
        case productBuildVersion = "ProductBuildVersion"
    }
}
