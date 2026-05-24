import Foundation
@preconcurrency import Path

public struct ApplicationSupportMigrationService: Sendable {
    public enum Result: Equatable, Sendable {
        case noMigrationNeeded
        case migratedOldSupportFiles
        case removedOldSupportFiles
    }

    public typealias FileExists = @Sendable (String) -> Bool
    public typealias MoveItem = @Sendable (URL, URL) throws -> Void
    public typealias RemoveItem = @Sendable (URL) throws -> Void

    private let fileExists: FileExists
    private let moveItem: MoveItem
    private let removeItem: RemoveItem

    public init(
        fileExists: @escaping FileExists = { path in FileManager.default.fileExists(atPath: path) },
        moveItem: @escaping MoveItem = { source, destination in try FileManager.default.moveItem(at: source, to: destination) },
        removeItem: @escaping RemoveItem = { url in try FileManager.default.removeItem(at: url) }
    ) {
        self.fileExists = fileExists
        self.moveItem = moveItem
        self.removeItem = removeItem
    }

    public func migrate(oldSupportPath: Path, newSupportPath: Path) -> Result {
        guard fileExists(oldSupportPath.string) else {
            return .noMigrationNeeded
        }

        if fileExists(newSupportPath.string) {
            try? removeItem(oldSupportPath.url)
            return .removedOldSupportFiles
        } else {
            try? moveItem(oldSupportPath.url, newSupportPath.url)
            return .migratedOldSupportFiles
        }
    }
}
