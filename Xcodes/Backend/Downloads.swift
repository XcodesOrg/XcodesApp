import Foundation
import Path
import Version

struct Downloads: Codable {
    let downloads: [Download]
}

public struct Download: Codable {
    public let name: String
    public let files: [File]
    public let dateModified: Date

    public struct File: Codable {
        public let remotePath: String
    }
}
