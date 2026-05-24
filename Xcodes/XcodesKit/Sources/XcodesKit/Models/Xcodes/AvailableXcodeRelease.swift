import Foundation
@preconcurrency import Version

/// A source-neutral Xcode release that can be mapped into app- or CLI-specific state.
public struct AvailableXcodeRelease: Codable, Sendable {
    public let version: Version
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
        url.path
    }

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
        self.version = version
        self.url = url
        self.filename = filename
        self.releaseDate = releaseDate
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.sdks = sdks
        self.compilers = compilers
        self.fileSize = fileSize
        self.architectures = architectures
    }
}
