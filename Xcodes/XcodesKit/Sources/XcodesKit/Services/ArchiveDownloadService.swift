import Foundation
@preconcurrency import Path

public struct ArchiveDownloadService: Sendable {
    public typealias Aria2Download = @Sendable (Path, URL, Path, [HTTPCookie]) -> AsyncThrowingStream<Progress, Error>
    public typealias URLSessionDownload = @Sendable (URL, URL, Data?) -> (progress: Progress, task: Task<(saveLocation: URL, response: URLResponse), Error>)
    public typealias ResponseValidator = @Sendable (URLResponse) throws -> Void
    public typealias ErrorFactory = @Sendable () -> Error

    private let aria2Download: Aria2Download
    private let urlSessionDownload: URLSessionDownload
    private let contentsAtPath: @Sendable (String) -> Data?
    private let createFile: @Sendable (String, Data) -> Void
    private let removeItem: @Sendable (URL) throws -> Void
    private let shouldRetry: @Sendable (Error) -> Bool
    private let validateResponse: ResponseValidator

    public init(
        aria2Download: @escaping Aria2Download,
        urlSessionDownload: @escaping URLSessionDownload,
        contentsAtPath: @escaping @Sendable (String) -> Data?,
        createFile: @escaping @Sendable (String, Data) -> Void,
        removeItem: @escaping @Sendable (URL) throws -> Void,
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
        validateResponse: @escaping ResponseValidator = { _ in }
    ) {
        self.aria2Download = aria2Download
        self.urlSessionDownload = urlSessionDownload
        self.contentsAtPath = contentsAtPath
        self.createFile = createFile
        self.removeItem = removeItem
        self.shouldRetry = shouldRetry
        self.validateResponse = validateResponse
    }

    public func downloadWithAria2(
        aria2Path: Path,
        url: URL,
        destination: Path,
        cookies: [HTTPCookie],
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await attemptRetryableTask(shouldRetry: shouldRetry) {
            let progressStream = aria2Download(aria2Path, url, destination, cookies)

            for try await progress in progressStream {
                progressChanged(progress)
            }

            return destination.url
        }
    }

    public func downloadWithURLSession(
        url: URL,
        destination: Path,
        resumeDataPath: Path,
        progressChanged: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        let persistedResumeData = contentsAtPath(resumeDataPath.string)

        do {
            let url = try await attemptResumableTask(shouldRetry: shouldRetry) { resumeData -> URL in
                let (progress, task) = urlSessionDownload(
                    url,
                    destination.url,
                    resumeData ?? persistedResumeData
                )
                progressChanged(progress)

                let result = try await task.value
                try validateResponse(result.response)
                return result.saveLocation
            }
            try? removeItem(resumeDataPath.url)
            return url
        } catch {
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                createFile(resumeDataPath.string, resumeData)
            }

            throw error
        }
    }

    public static func resumeDataPath(for archive: XcodeArchive, in directory: Path) -> Path {
        directory/"Xcode-\(archive.version).resumedata"
    }

    /// Apple redirects unauthorized downloads to an HTML page with a 200 status. Treat that
    /// as an authorization failure before the caller tries to unarchive the page as a XIP.
    public static func validateDeveloperDownloadResponse(
        _ response: URLResponse,
        unauthorizedError: ErrorFactory = { XcodesKitError("Received 403: Unauthorized.") }
    ) throws {
        guard response.url?.lastPathComponent != "unauthorized" else {
            throw unauthorizedError()
        }
    }
}
