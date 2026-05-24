import XCTest

final class ProgressXcodesTests: XCTestCase {
    func testUpdateFromAria2Output() {
        let progress = Progress()

        progress.updateFromAria2(string: "[#123abc 1024B/4096B(25%) CN:4 DL:512B ETA:1m2s]")

        XCTAssertEqual(progress.completedUnitCount, 1024)
        XCTAssertEqual(progress.totalUnitCount, 4096)
        XCTAssertEqual(progress.throughput, 512)
        XCTAssertEqual(progress.estimatedTimeRemaining, 62)
    }

    func testUpdateFromXcodebuildDownloadOutput() {
        let progress = Progress()

        progress.updateFromXcodebuild(text: "Downloading iOS 18.1 Simulator (22B83): 42.6% (1.2 GB of 2.8 GB)")

        XCTAssertEqual(progress.totalUnitCount, 100)
        XCTAssertEqual(progress.completedUnitCount, 43)
    }

    func testUpdateFromXcodebuildInstallingOutputIsIndeterminate() {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 50

        progress.updateFromXcodebuild(text: "Downloading tvOS 18.1 Simulator (22J5567a): Installing...")

        XCTAssertEqual(progress.totalUnitCount, 0)
        XCTAssertEqual(progress.completedUnitCount, 0)
    }
}
