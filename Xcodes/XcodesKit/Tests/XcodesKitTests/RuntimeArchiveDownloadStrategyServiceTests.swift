import XCTest
@preconcurrency import Path
@testable import XcodesKit

final class RuntimeArchiveDownloadStrategyServiceTests: XCTestCase {
    func testAria2StrategyValidatesDownloadPathAndForwardsProgress() async throws {
        let runtime = downloadableRuntime(source: "https://example.com/runtimes/iOS.dmg")
        let destination = try XCTUnwrap(Path("/tmp/iOS.dmg"))
        let aria2Path = try XCTUnwrap(Path("/usr/local/bin/aria2c"))
        let recorder = RuntimeArchiveDownloadRecorder()
        let progress = Progress(totalUnitCount: 10)
        progress.completedUnitCount = 4

        let service = RuntimeArchiveDownloadStrategyService(
            validateDownloadPath: { path in
                await recorder.recordValidation(path)
            },
            aria2Path: { aria2Path },
            aria2Download: { runtime, destination, aria2Path, _ in
                AsyncThrowingStream { continuation in
                    Task {
                        await recorder.recordAria2(runtime: runtime, destination: destination, aria2Path: aria2Path)
                        continuation.yield(progress)
                        continuation.finish()
                    }
                }
            }
        )

        let result = try await service.download(
            runtime: runtime,
            url: try XCTUnwrap(runtime.url),
            destination: destination,
            downloader: .aria2,
            progressChanged: { progress in
                Task { await recorder.recordProgress(progress.fractionCompleted) }
            }
        )

        XCTAssertEqual(result, destination.url)
        await recorder.waitForProgress(count: 1)
        let recorded = await recorder.snapshot()
        XCTAssertEqual(recorded.validatedPath, "/runtimes/iOS.dmg")
        XCTAssertEqual(recorded.aria2Runtime, runtime)
        XCTAssertEqual(recorded.aria2Destination, destination)
        XCTAssertEqual(recorded.aria2Path, aria2Path)
        XCTAssertEqual(recorded.progressFractions, [0.4])
    }

    func testURLSessionStrategyUsesProvidedDownload() async throws {
        let runtime = downloadableRuntime(source: "https://example.com/runtimes/iOS.dmg")
        let destination = try XCTUnwrap(Path("/tmp/iOS.dmg"))
        let recorder = RuntimeArchiveDownloadRecorder()

        let service = RuntimeArchiveDownloadStrategyService(
            validateDownloadPath: { path in
                await recorder.recordValidation(path)
            },
            aria2Path: {
                XCTFail("aria2 path should not be needed for URLSession downloads")
                throw URLError(.unknown)
            },
            urlSessionDownload: { url, destination, _ in
                await recorder.recordURLSession(url: url, destination: destination)
                return destination.url
            }
        )

        let result = try await service.download(
            runtime: runtime,
            url: try XCTUnwrap(runtime.url),
            destination: destination,
            downloader: .urlSession,
            progressChanged: { _ in }
        )

        XCTAssertEqual(result, destination.url)
        let recorded = await recorder.snapshot()
        XCTAssertEqual(recorded.validatedPath, "/runtimes/iOS.dmg")
        XCTAssertEqual(recorded.urlSessionURL, runtime.url)
        XCTAssertEqual(recorded.urlSessionDestination, destination)
    }

    func testURLSessionStrategyThrowsWhenUnavailable() async throws {
        let runtime = downloadableRuntime(source: "https://example.com/runtimes/iOS.dmg")
        let destination = try XCTUnwrap(Path("/tmp/iOS.dmg"))
        let service = RuntimeArchiveDownloadStrategyService(
            validateDownloadPath: { _ in },
            aria2Path: { try XCTUnwrap(Path("/usr/local/bin/aria2c")) }
        )

        do {
            _ = try await service.download(
                runtime: runtime,
                url: try XCTUnwrap(runtime.url),
                destination: destination,
                downloader: .urlSession,
                progressChanged: { _ in }
            )
            XCTFail("Expected URLSession runtime downloads to throw when no URLSession download is supplied")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Downloading runtimes with URLSession is not supported. Please use aria2")
        }
    }

    private func downloadableRuntime(source: String?) -> DownloadableRuntime {
        DownloadableRuntime(
            category: .simulator,
            simulatorVersion: .init(buildUpdate: "20A360", version: "16.0"),
            source: source,
            architectures: nil,
            dictionaryVersion: 1,
            contentType: .diskImage,
            platform: .iOS,
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-16-0",
            version: "16.0",
            fileSize: 42,
            hostRequirements: nil,
            name: "iOS 16.0",
            authentication: .virtual
        )
    }
}

private actor RuntimeArchiveDownloadRecorder {
    private(set) var validatedPath: String?
    private(set) var aria2Runtime: DownloadableRuntime?
    private(set) var aria2Destination: Path?
    private(set) var aria2Path: Path?
    private(set) var urlSessionURL: URL?
    private(set) var urlSessionDestination: Path?
    private(set) var progressFractions: [Double] = []
    private var progressWaiters: [CheckedContinuation<Void, Never>] = []

    func recordValidation(_ path: String) {
        validatedPath = path
    }

    func recordAria2(runtime: DownloadableRuntime, destination: Path, aria2Path: Path) {
        aria2Runtime = runtime
        aria2Destination = destination
        self.aria2Path = aria2Path
    }

    func recordURLSession(url: URL, destination: Path) {
        urlSessionURL = url
        urlSessionDestination = destination
    }

    func recordProgress(_ fraction: Double) {
        progressFractions.append(fraction)
        progressWaiters.forEach { $0.resume() }
        progressWaiters.removeAll()
    }

    func waitForProgress(count: Int) async {
        if progressFractions.count >= count { return }
        await withCheckedContinuation { continuation in
            progressWaiters.append(continuation)
        }
    }

    func snapshot() -> RuntimeArchiveDownloadRecord {
        RuntimeArchiveDownloadRecord(
            validatedPath: validatedPath,
            aria2Runtime: aria2Runtime,
            aria2Destination: aria2Destination,
            aria2Path: aria2Path,
            urlSessionURL: urlSessionURL,
            urlSessionDestination: urlSessionDestination,
            progressFractions: progressFractions
        )
    }
}

private struct RuntimeArchiveDownloadRecord {
    let validatedPath: String?
    let aria2Runtime: DownloadableRuntime?
    let aria2Destination: Path?
    let aria2Path: Path?
    let urlSessionURL: URL?
    let urlSessionDestination: Path?
    let progressFractions: [Double]
}
