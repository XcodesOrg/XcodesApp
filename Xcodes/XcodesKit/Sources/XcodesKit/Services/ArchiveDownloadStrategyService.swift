import Foundation
@preconcurrency import Path

public struct ArchiveDownloadStrategyService: Sendable {
    public typealias Aria2Path = @Sendable () throws -> Path
    public typealias CookiesForURL = @Sendable (URL) -> [HTTPCookie]

    private let archiveDownloadService: ArchiveDownloadService
    private let aria2Path: Aria2Path
    private let cookiesForURL: CookiesForURL

    public init(
        archiveDownloadService: ArchiveDownloadService,
        aria2Path: @escaping Aria2Path,
        cookiesForURL: @escaping CookiesForURL = { _ in [] }
    ) {
        self.archiveDownloadService = archiveDownloadService
        self.aria2Path = aria2Path
        self.cookiesForURL = cookiesForURL
    }

    public func download(
        url: URL,
        destination: Path,
        downloader: XcodeArchiveDownloader,
        resumeDataPath: Path,
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        switch downloader {
        case .aria2:
            return try await archiveDownloadService.downloadWithAria2(
                aria2Path: aria2Path(),
                url: url,
                destination: destination,
                cookies: cookiesForURL(url),
                progressChanged: progressChanged
            )
        case .urlSession:
            return try await archiveDownloadService.downloadWithURLSession(
                url: url,
                destination: destination,
                resumeDataPath: resumeDataPath,
                progressChanged: progressChanged
            )
        }
    }

    public func download(
        archive: XcodeArchive,
        destination: Path,
        downloader: XcodeArchiveDownloader,
        applicationSupportPath: Path,
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await download(
            url: archive.downloadURL,
            destination: destination,
            downloader: downloader,
            resumeDataPath: ArchiveDownloadService.resumeDataPath(for: archive, in: applicationSupportPath),
            progressChanged: progressChanged
        )
    }
}
