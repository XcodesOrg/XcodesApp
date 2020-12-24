import Foundation
import Version
import Path

/// A version of Xcode that's already installed
public struct InstalledXcode: Equatable {
    public let path: Path
    /// Composed of the bundle short version from Info.plist and the product build version from version.plist
    public let version: Version

    public init?(path: Path) {
        self.path = path

        let infoPlistPath = path.join("Contents").join("Info.plist")
        let versionPlistPath = path.join("Contents").join("version.plist")
        guard 
            let infoPlistData = Current.files.contents(atPath: infoPlistPath.string),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData),
            let bundleShortVersion = infoPlist.bundleShortVersion,
            let bundleVersion = Version(tolerant: bundleShortVersion),

            let versionPlistData = Current.files.contents(atPath: versionPlistPath.string),
            let versionPlist = try? PropertyListDecoder().decode(VersionPlist.self, from: versionPlistData)
        else { return nil }

        // Installed betas don't include the beta number anywhere, so try to parse it from the filename or fall back to simply "beta"
        var prereleaseIdentifiers = bundleVersion.prereleaseIdentifiers
        if let filenameVersion = Version(path.basename(dropExtension: true).replacingOccurrences(of: "Xcode-", with: "")) {
            prereleaseIdentifiers = filenameVersion.prereleaseIdentifiers
        }
        else if infoPlist.bundleIconName == "XcodeBeta", !prereleaseIdentifiers.contains("beta") {
            prereleaseIdentifiers = ["beta"]
        }

        self.version = Version(major: bundleVersion.major,
                               minor: bundleVersion.minor,
                               patch: bundleVersion.patch,
                               prereleaseIdentifiers: prereleaseIdentifiers,
                               buildMetadataIdentifiers: [versionPlist.productBuildVersion].compactMap { $0 })
    }
}

public struct InfoPlist: Decodable {
    public let bundleID: String?
    public let bundleShortVersion: String?
    public let bundleIconName: String?

    public enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier"
        case bundleShortVersion = "CFBundleShortVersionString"
        case bundleIconName = "CFBundleIconName"
    }
}

public struct VersionPlist: Decodable {
    public let productBuildVersion: String

    public enum CodingKeys: String, CodingKey {
        case productBuildVersion = "ProductBuildVersion"
    }
}
