import Foundation
@preconcurrency import Path
@preconcurrency import Version

public struct XcodeArchive: Sendable {
    public let version: Version
    public let downloadURL: URL
    public let filename: String

    public init(version: Version, downloadURL: URL, filename: String) {
        self.version = version
        self.downloadURL = downloadURL
        self.filename = filename
    }
}

public enum XcodeArchiveDownloader: String, CaseIterable, Identifiable, CustomStringConvertible, Sendable {
    case urlSession
    case aria2

    public var id: Self { self }

    public var description: String {
        switch self {
        case .urlSession: return "URLSession"
        case .aria2: return "aria2"
        }
    }
}

public struct XcodeArchiveService: Sendable {
    public typealias Download = @Sendable (XcodeArchive, Path, XcodeArchiveDownloader, @escaping @Sendable (Progress) -> Void) async throws -> URL

    private let applicationSupportPath: Path
    private let fileExists: @Sendable (Path) -> Bool
    private let download: Download

    public init(
        applicationSupportPath: Path,
        fileExists: @escaping @Sendable (Path) -> Bool,
        download: @escaping Download
    ) {
        self.applicationSupportPath = applicationSupportPath
        self.fileExists = fileExists
        self.download = download
    }

    public func archiveURL(
        for archive: XcodeArchive,
        downloader: XcodeArchiveDownloader,
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        if let existingArchiveURL = existingArchiveURL(for: archive, downloader: downloader) {
            return existingArchiveURL
        }

        return try await download(archive, expectedArchivePath(for: archive), downloader, progressChanged)
    }

    public func existingArchiveURL(
        for archive: XcodeArchive,
        downloader: XcodeArchiveDownloader
    ) -> URL? {
        let destination = expectedArchivePath(for: archive)
        let metadataPath = aria2MetadataPath(for: destination)
        let aria2DownloadIsIncomplete = downloader == .aria2 && fileExists(metadataPath)

        if fileExists(destination), aria2DownloadIsIncomplete == false {
            return destination.url
        }

        return nil
    }

    public func expectedArchivePath(for archive: XcodeArchive) -> Path {
        applicationSupportPath/"Xcode-\(archive.version).\(archive.filename.suffix(fromLast: "."))"
    }

    public func aria2MetadataPath(for archivePath: Path) -> Path {
        archivePath.parent/(archivePath.basename() + ".aria2")
    }
}
