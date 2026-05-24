import Foundation
@preconcurrency import Path

public struct CodableFileStore<Value: Codable & Sendable>: Sendable {
    public typealias Attributes = [FileAttributeKey: Any]
    public typealias ContentsAtPath = @Sendable (String) -> Data?
    public typealias CreateDirectory = @Sendable (URL, Bool, Attributes?) throws -> Void
    public typealias CreateFile = @Sendable (String, Data?, Attributes?) -> Bool
    public typealias Decode = @Sendable (Data) throws -> Value
    public typealias Encode = @Sendable (Value) throws -> Data

    private let contentsAtPath: ContentsAtPath
    private let createDirectory: CreateDirectory
    private let createFile: CreateFile
    private let decode: Decode
    private let encode: Encode

    public init(
        contentsAtPath: @escaping ContentsAtPath = { path in FileManager.default.contents(atPath: path) },
        createDirectory: @escaping CreateDirectory = { url, createIntermediates, attributes in
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
        },
        createFile: @escaping CreateFile = { path, data, attributes in
            FileManager.default.createFile(atPath: path, contents: data, attributes: attributes)
        },
        decode: @escaping Decode = { data in try JSONDecoder().decode(Value.self, from: data) },
        encode: @escaping Encode = { value in try JSONEncoder().encode(value) }
    ) {
        self.contentsAtPath = contentsAtPath
        self.createDirectory = createDirectory
        self.createFile = createFile
        self.decode = decode
        self.encode = encode
    }

    public func load(from file: Path) throws -> Value? {
        guard let data = contentsAtPath(file.string) else { return nil }
        return try decode(data)
    }

    public func save(_ value: Value, to file: Path) throws {
        let data = try encode(value)
        try createDirectory(file.url.deletingLastPathComponent(), true, nil)
        _ = createFile(file.string, data, nil)
    }
}
