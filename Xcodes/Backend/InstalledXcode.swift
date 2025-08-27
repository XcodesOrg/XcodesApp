import Foundation
import Version
import Path
import XcodesKit

/// A version of Xcode that's already installed
public struct InstalledXcode: Equatable {
    public let path: Path
    public let xcodeID: XcodeID
    
    /// Composed of the bundle short version from Info.plist and the product build version from version.plist
    public var version: Version {
        return xcodeID.version
    }

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
        
        let archsString = try? XcodesKit.Current.shell.archs(path.url.appending(path: "Contents/MacOS/Xcode")).out
        
        let architectures = archsString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .compactMap { Architecture(rawValue: String($0)) }
        
        let version = Version(major: bundleVersion.major,
                               minor: bundleVersion.minor,
                               patch: bundleVersion.patch,
                               prereleaseIdentifiers: prereleaseIdentifiers,
                               buildMetadataIdentifiers: [versionPlist.productBuildVersion].compactMap { $0 })
        
        self.xcodeID = XcodeID(version: version, architectures: architectures)
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
