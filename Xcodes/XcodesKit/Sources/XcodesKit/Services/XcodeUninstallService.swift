import Foundation

public struct XcodeUninstallService: Sendable {
    public struct Result: Equatable, Sendable {
        public let xcode: InstalledXcode
        public let trashURL: URL?

        public var didDeleteImmediately: Bool {
            trashURL == nil
        }
    }

    private let removeItem: @Sendable (URL) throws -> Void
    private let trashItem: @Sendable (URL) throws -> URL

    public init(
        removeItem: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        trashItem: @escaping @Sendable (URL) throws -> URL = { try FileManager.default.xcodesTrashItem(at: $0) }
    ) {
        self.removeItem = removeItem
        self.trashItem = trashItem
    }

    public func uninstall(_ xcode: InstalledXcode, emptyTrash: Bool) throws -> Result {
        if emptyTrash {
            try removeItem(xcode.path.url)
            return Result(xcode: xcode, trashURL: nil)
        }

        return Result(xcode: xcode, trashURL: try trashItem(xcode.path.url))
    }
}
