import Foundation
import Path
import Version

struct Downloads: Codable {
    let downloads: [Download]
}

// Set to Int64 as ByteCountFormatter uses it.
public typealias ByteCount = Int64

public struct Download: Codable {
    public let name: String
    public let files: [File]
    public let dateModified: Date

    public struct File: Codable {
        public let remotePath: String
        public let fileSize: ByteCount
    }
}
