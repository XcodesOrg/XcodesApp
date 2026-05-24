import Foundation
@preconcurrency import Path

public struct DownloadableRuntimeCache: Sendable {
    public typealias Attributes = [FileAttributeKey: Any]
    public typealias ContentsAtPath = @Sendable (String) -> Data?
    public typealias WriteData = @Sendable (Data, URL) throws -> Void
    public typealias CreateDirectory = @Sendable (URL, Bool, Attributes?) throws -> Void

    public let cacheFile: Path
    private let contentsAtPath: ContentsAtPath
    private let writeData: WriteData
    private let createDirectory: CreateDirectory

    public init(
        cacheFile: Path,
        contentsAtPath: @escaping ContentsAtPath = { FileManager.default.contents(atPath: $0) },
        writeData: @escaping WriteData = { try $0.write(to: $1) },
        createDirectory: @escaping CreateDirectory = { url, createIntermediates, attributes in
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
        }
    ) {
        self.cacheFile = cacheFile
        self.contentsAtPath = contentsAtPath
        self.writeData = writeData
        self.createDirectory = createDirectory
    }

    public func load() throws -> [DownloadableRuntime]? {
        guard let data = contentsAtPath(cacheFile.string) else { return nil }
        return try JSONDecoder().decode([DownloadableRuntime].self, from: data)
    }

    public func save(_ runtimes: [DownloadableRuntime]) throws {
        let data = try JSONEncoder().encode(runtimes)
        try createDirectory(cacheFile.url.deletingLastPathComponent(), true, nil)
        try writeData(data, cacheFile.url)
    }
}
