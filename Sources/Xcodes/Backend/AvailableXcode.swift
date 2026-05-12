import Foundation
import Version
import XcodesKit

/// A version of Xcode that's available for installation
public struct AvailableXcode: Codable {
    public var version: Version {
        return xcodeID.version
    }
    public let url: URL
    public let filename: String
    public let releaseDate: Date?
    public let requiredMacOSVersion: String?
    public let releaseNotesURL: URL?
    public let sdks: SDKs?
    public let compilers: Compilers?
    public let fileSize: Int64?
    public let architectures: [Architecture]?
    public var downloadPath: String {
        return url.path
    }
    public var xcodeID: XcodeID

    public init(
        version: Version,
        url: URL,
        filename: String,
        releaseDate: Date?,
        requiredMacOSVersion: String? = nil,
        releaseNotesURL: URL? = nil,
        sdks: SDKs? = nil,
        compilers: Compilers? = nil,
        fileSize: Int64? = nil,
        architectures: [Architecture]? = nil
    ) {
        self.url = url
        self.filename = filename
        self.releaseDate = releaseDate
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.sdks = sdks
        self.compilers = compilers
        self.fileSize = fileSize
        self.architectures = architectures
        self.xcodeID = XcodeID(version: version, architectures: architectures)
    }
}
