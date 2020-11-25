import Foundation
import Path

public struct Configuration: Codable {
    public var defaultUsername: String?

    public init() {
        self.defaultUsername = nil
    }

    public mutating func load() throws {
        guard let data = Current.files.contents(atPath: Path.configurationFile.string) else { return }
        self = try JSONDecoder().decode(Configuration.self, from: data)
    }

    public func save() throws {
        let data = try JSONEncoder().encode(self)
        try Current.files.createDirectory(at: Path.configurationFile.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        Current.files.createFile(atPath: Path.configurationFile.string, contents: data)
    }
}
