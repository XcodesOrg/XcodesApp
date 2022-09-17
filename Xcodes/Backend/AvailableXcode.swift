import Foundation
import Version
import struct XCModel.SDKs
import struct XCModel.Compilers

/// A version of Xcode that's available for installation
public struct AvailableXcode: Codable {
    public var version: Version
    public let url: URL
    public let filename: String
    public let releaseDate: Date?
    public let requiredMacOSVersion: String?
    public let releaseNotesURL: URL?
    public let sdks: SDKs?
    public let compilers: Compilers?
    public let fileSize: Int64?
    public var downloadPath: String {
        return url.path
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
        fileSize: Int64? = nil
    ) {
        self.version =  version
        self.url = url
        self.filename = filename
        self.releaseDate = releaseDate
        self.requiredMacOSVersion = requiredMacOSVersion
        self.releaseNotesURL = releaseNotesURL
        self.sdks = sdks
        self.compilers = compilers
        self.fileSize = fileSize
    }
}
