import Foundation

public struct Downloads: Codable, Sendable {
    public let resultCode: Int?
    public let resultsString: String?
    public let downloads: [Download]?

    public init(resultCode: Int? = nil, resultsString: String? = nil, downloads: [Download]?) {
        self.resultCode = resultCode
        self.resultsString = resultsString
        self.downloads = downloads
    }

    public var hasError: Bool {
        (resultCode ?? 0) != 0
    }
}

public typealias ByteCount = Int64

public struct Download: Codable, Sendable {
    public let name: String
    public let files: [File]
    public let dateModified: Date

    public init(name: String, files: [File], dateModified: Date) {
        self.name = name
        self.files = files
        self.dateModified = dateModified
    }

    public struct File: Codable, Sendable {
        public let remotePath: String
        public let fileSize: ByteCount?

        public init(remotePath: String, fileSize: ByteCount? = nil) {
            self.remotePath = remotePath
            self.fileSize = fileSize
        }
    }
}
