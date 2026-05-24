import Foundation
@preconcurrency import Path

public struct ArchiveCancellationCleanupService: Sendable {
    public typealias RemoveItem = @Sendable (URL) throws -> Void

    private let removeItem: RemoveItem

    public init(removeItem: @escaping RemoveItem = { url in try FileManager.default.removeItem(at: url) }) {
        self.removeItem = removeItem
    }

    public func cleanupXcodeArchive(
        for xcode: AvailableXcode,
        applicationSupportPath: Path
    ) {
        let service = XcodeArchiveService(
            applicationSupportPath: applicationSupportPath,
            fileExists: { _ in false },
            download: { _, _, _, _ in throw XcodesKitError("Archive cleanup does not download") }
        )
        cleanupArchive(at: service.expectedArchivePath(for: XcodeArchive(xcode)))
    }

    public func cleanupRuntimeArchive(
        for runtime: DownloadableRuntime,
        destinationDirectory: Path
    ) {
        let service = RuntimeArchiveService(
            fileExists: { _ in false },
            download: { _, _, _, _, _ in throw XcodesKitError("Archive cleanup does not download") }
        )
        cleanupArchive(at: service.expectedArchivePath(for: runtime, destinationDirectory: destinationDirectory))
    }

    public func cleanupArchive(at archivePath: Path) {
        try? removeItem(archivePath.url)
        try? removeItem(aria2MetadataPath(for: archivePath).url)
    }

    public func aria2MetadataPath(for archivePath: Path) -> Path {
        archivePath.parent/(archivePath.basename() + ".aria2")
    }
}
