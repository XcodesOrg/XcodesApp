import Foundation
@preconcurrency import Path

public struct RuntimeArchiveService: Sendable {
    public typealias Download = @Sendable (DownloadableRuntime, URL, Path, XcodeArchiveDownloader, @escaping @Sendable (Progress) -> Void) async throws -> URL

    private let fileExists: @Sendable (Path) -> Bool
    private let download: Download

    public init(
        fileExists: @escaping @Sendable (Path) -> Bool,
        download: @escaping Download
    ) {
        self.fileExists = fileExists
        self.download = download
    }

    public func archiveURL(
        for runtime: DownloadableRuntime,
        destinationDirectory: Path,
        downloader: XcodeArchiveDownloader,
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        guard let url = runtime.url else {
            throw XcodesKitError("Invalid or non existent runtime url")
        }

        let destination = expectedArchivePath(for: runtime, destinationDirectory: destinationDirectory)
        let metadataPath = aria2MetadataPath(for: destination)
        let aria2DownloadIsIncomplete = downloader == .aria2 && fileExists(metadataPath)

        if fileExists(destination), aria2DownloadIsIncomplete == false {
            return destination.url
        }

        return try await download(runtime, url, destination, downloader, progressChanged)
    }

    public func expectedArchivePath(for runtime: DownloadableRuntime, destinationDirectory: Path) -> Path {
        guard let url = runtime.url else {
            return destinationDirectory/runtime.identifier
        }
        return destinationDirectory/url.lastPathComponent
    }

    public func aria2MetadataPath(for archivePath: Path) -> Path {
        archivePath.parent/(archivePath.basename() + ".aria2")
    }

    public static func downloadWithAria2(
        runtime: DownloadableRuntime,
        to destination: Path,
        aria2Path: Path,
        cookiesForURL: @escaping @Sendable (URL) -> [HTTPCookie]
    ) -> AsyncThrowingStream<Progress, Error> {
        guard let url = runtime.url else {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Progress.self, throwing: Error.self)
            continuation.finish(throwing: XcodesKitError("Invalid or non existent runtime url"))
            return stream
        }

        return Aria2DownloadService().download(
            aria2Path: aria2Path,
            url: url,
            destination: destination,
            cookies: cookiesForURL(url)
        )
    }
}
