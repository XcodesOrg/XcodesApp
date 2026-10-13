import AppKit
import Foundation
import Path
import Version
import XcodesKit

struct Xcode: Identifiable, CustomStringConvertible {
    var version: Version {
        return id.version
    }
    /// Other Xcode versions that have the same build identifier
    let identicalBuilds: [XcodeID]
    var installState: XcodeInstallState
    let selected: Bool
    let icon: NSImage?
    let requiredMacOSVersion: String?
    let releaseNotesURL: URL?
    let releaseDate: Date?
    let sdks: SDKs?
    let compilers: Compilers?
    let downloadFileSize: Int64?
    let architectures: [Architecture]?
    /// SDK build identifiers read from the installed bundle, used when the data source has no SDK metadata
    let installedSDKBuilds: [String]
    let id: XcodeID
    
    init(
        version: Version,
        identicalBuilds: [XcodeID] = [],
        installState: XcodeInstallState,
        selected: Bool,
        icon: NSImage?,
        requiredMacOSVersion: String? = nil,
        releaseNotesURL: URL? = nil,
        releaseDate: Date? = nil,
        sdks: SDKs? = nil,
        compilers: Compilers? = nil,
        downloadFileSize: Int64? = nil,
        architectures: [Architecture]? = nil,
        installedSDKBuilds: [String] = []
    ) {
        self.identicalBuilds = identicalBuilds
        self.installState = installState
        self.selected = selected
        self.icon = icon
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.releaseDate = releaseDate
        self.sdks = sdks
        self.compilers = compilers
        self.downloadFileSize = downloadFileSize
        self.architectures = architectures
        self.installedSDKBuilds = installedSDKBuilds
        self.id = XcodeID(version: version, architectures: architectures)
    }

    init(_ item: XcodeListItem, icon: NSImage?, installedSDKBuilds: [String] = []) {
        self.identicalBuilds = item.identicalBuilds
        self.installState = item.installState
        self.selected = item.selected
        self.icon = icon
        self.requiredMacOSVersion = item.requiredMacOSVersion
        self.releaseNotesURL = item.releaseNotesURL
        self.releaseDate = item.releaseDate
        self.sdks = item.sdks
        self.compilers = item.compilers
        self.downloadFileSize = item.downloadFileSize
        self.architectures = item.architectures
        self.installedSDKBuilds = installedSDKBuilds
        self.id = item.id
    }

    var listItem: XcodeListItem {
        XcodeListItem(
            version: version,
            identicalBuilds: identicalBuilds,
            installState: installState,
            selected: selected,
            requiredMacOSVersion: requiredMacOSVersion,
            releaseNotesURL: releaseNotesURL,
            releaseDate: releaseDate,
            sdks: sdks,
            compilers: compilers,
            downloadFileSize: downloadFileSize,
            architectures: architectures
        )
    }
    
    var description: String {
        version.appleDescription
    }

    var identicalBuildsForCurrentVariant: [XcodeID] {
        identicalBuilds.filter { $0.architectures == architectures }
    }
    
    var downloadFileSizeString: String? {
        listItem.downloadFileSizeString
    }
    
    var installedPath: Path? {
        installState.installedPath
    }

    /// SDK builds used to find matching platform runtimes. An installed bundle is the source of truth,
    /// since the Apple data source has no SDK metadata and a renamed beta may not match its release.
    var platformSDKBuilds: [String] {
        installedSDKBuilds.isEmpty ? (sdks?.allBuilds ?? []) : installedSDKBuilds
    }
}

enum InstalledSDKBuilds {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [String]] = [:]

    /// Reads the ProductBuildVersion of each SDK in an installed Xcode, e.g. iPhoneOS.sdk -> 24A5422a.
    static func builds(forXcodeAt path: Path, version: Version) -> [String] {
        let key = "\(path.string)|\(version.buildMetadataIdentifiers.joined())"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let fileManager = FileManager.default
        let platformsURL = path.url.appending(path: "Contents/Developer/Platforms")
        let platformURLs = (try? fileManager.contentsOfDirectory(at: platformsURL, includingPropertiesForKeys: nil)) ?? []
        var builds: [String] = []
        for platformURL in platformURLs where platformURL.pathExtension == "platform" {
            let sdksURL = platformURL.appending(path: "Developer/SDKs")
            let sdkURLs = (try? fileManager.contentsOfDirectory(at: sdksURL, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
            for sdkURL in sdkURLs where sdkURL.pathExtension == "sdk" {
                // Versioned SDK names (e.g. iPhoneOS27.0.sdk) are symlinks to the same SDK
                if (try? sdkURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                let systemVersionURL = sdkURL.appending(path: "System/Library/CoreServices/SystemVersion.plist")
                guard
                    let data = Current.files.contents(atPath: systemVersionURL.path),
                    let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                    let build = plist["ProductBuildVersion"] as? String,
                    !builds.contains(build)
                else { continue }
                builds.append(build)
            }
        }

        lock.lock()
        cache[key] = builds
        lock.unlock()
        return builds
    }
}
