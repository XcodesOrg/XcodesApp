import Foundation
import Version

/// A version of Xcode that's available for installation
public struct AvailableXcode: Codable {
    public let version: Version
    public let url: URL
    public let filename: String
    public let releaseDate: Date?

    public init(version: Version, url: URL, filename: String, releaseDate: Date?) {
        self.version =  version
        self.url = url
        self.filename = filename
        self.releaseDate = releaseDate
    }
}
