import XCTest
@preconcurrency import Path
@testable import XcodesKit

final class ArchiveDownloadStrategyServiceTests: XCTestCase {
    func testAria2StrategyUsesAria2PathCookiesAndDestination() async throws {
        let aria2Path = try XCTUnwrap(Path("/usr/local/bin/aria2c"))
        let url = try XCTUnwrap(URL(string: "https://example.com/Xcode.xip"))
        let destination = try XCTUnwrap(Path("/tmp/Xcode.xip"))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "cookie"
        ]))
        let recorder = Aria2Recorder()
        let service = ArchiveDownloadStrategyService(
            archiveDownloadService: ArchiveDownloadService(
                aria2Download: { path, url, destination, cookies in
                    return AsyncThrowingStream { continuation in
                        Task {
                            await recorder.record(path: path, url: url, destination: destination, cookies: cookies)
                            continuation.finish()
                        }
                    }
                },
                urlSessionDownload: { _, _, _ in
                    XCTFail("URLSession should not be used for aria2 downloads")
                    return (Progress(), Task { throw URLError(.unknown) })
                },
                contentsAtPath: { _ in nil },
                createFile: { _, _ in },
                removeItem: { _ in }
            ),
            aria2Path: { aria2Path },
            cookiesForURL: { _ in [cookie] }
        )

        let result = try await service.download(
            url: url,
            destination: destination,
            downloader: .aria2,
            resumeDataPath: try XCTUnwrap(Path("/tmp/Xcode.xip.resumedata")),
            progressChanged: { _ in }
        )

        XCTAssertEqual(result, destination.url)
        let recorded = await recorder.values
        XCTAssertEqual(recorded.path, aria2Path.string)
        XCTAssertEqual(recorded.url, url)
        XCTAssertEqual(recorded.destination, destination.string)
        XCTAssertEqual(recorded.cookies, [cookie])
    }

    func testURLSessionStrategyUsesResumeDataPathAndSkipsAria2() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/Xcode.xip"))
        let destination = try XCTUnwrap(Path("/tmp/Xcode.xip"))
        let resumeDataPath = try XCTUnwrap(Path("/tmp/Xcode.xip.resumedata"))
        let resumeData = Data("resume".utf8)
        let recorder = URLSessionRecorder()
        let service = ArchiveDownloadStrategyService(
            archiveDownloadService: ArchiveDownloadService(
                aria2Download: { _, _, _, _ in
                    XCTFail("aria2 should not be used for URLSession downloads")
                    return AsyncThrowingStream { continuation in
                        continuation.finish(throwing: URLError(.unknown))
                    }
                },
                urlSessionDownload: { url, destination, resumeData in
                    return (
                        Progress(),
                        Task {
                            await recorder.record(url: url, destination: destination, resumeData: resumeData)
                            return (
                                saveLocation: destination,
                                response: URLResponse(
                                    url: url,
                                    mimeType: nil,
                                    expectedContentLength: 0,
                                    textEncodingName: nil
                                )
                            )
                        }
                    )
                },
                contentsAtPath: { path in
                    path == resumeDataPath.string ? resumeData : nil
                },
                createFile: { _, _ in },
                removeItem: { _ in }
            ),
            aria2Path: {
                XCTFail("aria2 path should not be requested for URLSession downloads")
                return try XCTUnwrap(Path("/usr/local/bin/aria2c"))
            }
        )

        let result = try await service.download(
            url: url,
            destination: destination,
            downloader: .urlSession,
            resumeDataPath: resumeDataPath,
            progressChanged: { _ in }
        )

        XCTAssertEqual(result, destination.url)
        let recorded = await recorder.values
        XCTAssertEqual(recorded.url, url)
        XCTAssertEqual(recorded.destination, destination.url)
        XCTAssertEqual(recorded.resumeData, resumeData)
    }
}

private actor Aria2Recorder {
    private(set) var values: (path: String?, url: URL?, destination: String?, cookies: [HTTPCookie]?) = (nil, nil, nil, nil)

    func record(path: Path, url: URL, destination: Path, cookies: [HTTPCookie]) {
        values = (path.string, url, destination.string, cookies)
    }
}

private actor URLSessionRecorder {
    private(set) var values: (url: URL?, destination: URL?, resumeData: Data?) = (nil, nil, nil)

    func record(url: URL, destination: URL, resumeData: Data?) {
        values = (url, destination, resumeData)
    }
}
