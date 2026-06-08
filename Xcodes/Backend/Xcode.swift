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
        architectures: [Architecture]? = nil
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
        self.id = XcodeID(version: version, architectures: architectures)
    }

    init(_ item: XcodeListItem, icon: NSImage?) {
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
    
}
