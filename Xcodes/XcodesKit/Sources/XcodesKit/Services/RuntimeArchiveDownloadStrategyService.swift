import Foundation
@preconcurrency import Path

public struct RuntimeArchiveDownloadStrategyService: Sendable {
    public typealias ValidateDownloadPath = @Sendable (String) async throws -> Void
    public typealias Aria2Path = @Sendable () throws -> Path
    public typealias Aria2Download = @Sendable (DownloadableRuntime, Path, Path, @escaping @Sendable (URL) -> [HTTPCookie]) -> AsyncThrowingStream<Progress, Error>
    public typealias CookiesForURL = @Sendable (URL) -> [HTTPCookie]
    public typealias URLSessionDownload = @Sendable (URL, Path, @escaping @Sendable (Progress) -> Void) async throws -> URL
    public typealias MissingDownloadPathError = @Sendable (DownloadableRuntime) -> Error

    private let validateDownloadPath: ValidateDownloadPath
    private let aria2Path: Aria2Path
    private let aria2Download: Aria2Download
    private let cookiesForURL: CookiesForURL
    private let urlSessionDownload: URLSessionDownload?
    private let missingDownloadPathError: MissingDownloadPathError

    public init(
        validateDownloadPath: @escaping ValidateDownloadPath,
        aria2Path: @escaping Aria2Path,
        aria2Download: @escaping Aria2Download = { runtime, destination, aria2Path, cookiesForURL in
            RuntimeArchiveService.downloadWithAria2(
                runtime: runtime,
                to: destination,
                aria2Path: aria2Path,
                cookiesForURL: cookiesForURL
            )
        },
        cookiesForURL: @escaping CookiesForURL = { _ in [] },
        urlSessionDownload: URLSessionDownload? = nil,
        missingDownloadPathError: @escaping MissingDownloadPathError = { _ in XcodesKitError("Invalid runtime downloadPath") }
    ) {
        self.validateDownloadPath = validateDownloadPath
        self.aria2Path = aria2Path
        self.aria2Download = aria2Download
        self.cookiesForURL = cookiesForURL
        self.urlSessionDownload = urlSessionDownload
        self.missingDownloadPathError = missingDownloadPathError
    }

    public func download(
        runtime: DownloadableRuntime,
        url: URL,
        destination: Path,
        downloader: XcodeArchiveDownloader,
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        guard let downloadPath = runtime.downloadPath else {
            throw missingDownloadPathError(runtime)
        }

        try await validateDownloadPath(downloadPath)

        switch downloader {
        case .aria2:
            for try await progress in aria2Download(runtime, destination, try aria2Path(), cookiesForURL) {
                progressChanged(progress)
            }
            return destination.url
        case .urlSession:
            guard let urlSessionDownload else {
                throw XcodesKitError("Downloading runtimes with URLSession is not supported. Please use aria2")
            }

            return try await urlSessionDownload(url, destination, progressChanged)
        }
    }
}
