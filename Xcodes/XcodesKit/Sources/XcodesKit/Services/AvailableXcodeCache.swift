import Foundation
@preconcurrency import Path

public struct AvailableXcodeCache: Sendable {
    public typealias Attributes = [FileAttributeKey: Any]
    public typealias ContentsAtPath = @Sendable (String) -> Data?
    public typealias WriteData = @Sendable (Data, URL) throws -> Void
    public typealias CreateDirectory = @Sendable (URL, Bool, Attributes?) throws -> Void
    public typealias AttributesOfItem = @Sendable (String) throws -> Attributes

    public let cacheFile: Path
    private var contentsAtPath: ContentsAtPath
    private var writeData: WriteData
    private var createDirectory: CreateDirectory
    private var attributesOfItem: AttributesOfItem

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
        },
        attributesOfItem: @escaping AttributesOfItem = { try FileManager.default.attributesOfItem(atPath: $0) }
    ) {
        self.cacheFile = cacheFile
        self.contentsAtPath = contentsAtPath
        self.writeData = writeData
        self.createDirectory = createDirectory
        self.attributesOfItem = attributesOfItem
    }

    public func load() throws -> [AvailableXcode]? {
        guard let data = contentsAtPath(cacheFile.string) else { return nil }
        return try JSONDecoder().decode([AvailableXcode].self, from: data)
    }

    public func lastModified() -> Date? {
        let attributes = try? attributesOfItem(cacheFile.string)
        return attributes?[.modificationDate] as? Date
    }

    public func save(_ xcodes: [AvailableXcode]) throws {
        let data = try JSONEncoder().encode(xcodes)
        try createDirectory(cacheFile.url.deletingLastPathComponent(), true, nil)
        try writeData(data, cacheFile.url)
    }
}
