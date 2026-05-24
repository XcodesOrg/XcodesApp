@preconcurrency import Path
import XCTest
import os
@testable import XcodesKit

final class ApplicationSupportMigrationServiceTests: XCTestCase {
    private let oldSupportPath = Path("/tmp/old-support")!
    private let newSupportPath = Path("/tmp/new-support")!

    func testMigrationDoesNothingWhenOldSupportFilesDoNotExist() {
        let service = ApplicationSupportMigrationService(
            fileExists: { _ in false },
            moveItem: { _, _ in XCTFail("Should not move support files") },
            removeItem: { _ in XCTFail("Should not remove support files") }
        )

        XCTAssertEqual(
            service.migrate(oldSupportPath: oldSupportPath, newSupportPath: newSupportPath),
            .noMigrationNeeded
        )
    }

    func testMigrationMovesOldSupportFilesWhenNewSupportFilesDoNotExist() {
        let recorder = MigrationRecorder()
        let oldSupportPathString = oldSupportPath.string
        let service = ApplicationSupportMigrationService(
            fileExists: { $0 == oldSupportPathString },
            moveItem: { source, destination in
                recorder.recordMove(source: source, destination: destination)
            },
            removeItem: { _ in XCTFail("Should not remove support files") }
        )

        XCTAssertEqual(
            service.migrate(oldSupportPath: oldSupportPath, newSupportPath: newSupportPath),
            .migratedOldSupportFiles
        )
        XCTAssertEqual(recorder.movedSource, oldSupportPath.url)
        XCTAssertEqual(recorder.movedDestination, newSupportPath.url)
    }

    func testMigrationRemovesOldSupportFilesWhenNewSupportFilesAlreadyExist() {
        let recorder = MigrationRecorder()
        let service = ApplicationSupportMigrationService(
            fileExists: { _ in true },
            moveItem: { _, _ in XCTFail("Should not move support files") },
            removeItem: { recorder.recordRemoval($0) }
        )

        XCTAssertEqual(
            service.migrate(oldSupportPath: oldSupportPath, newSupportPath: newSupportPath),
            .removedOldSupportFiles
        )
        XCTAssertEqual(recorder.removedURL, oldSupportPath.url)
    }
}

private final class MigrationRecorder: Sendable {
    private struct State: Sendable {
        var source: URL?
        var destination: URL?
        var removed: URL?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var movedSource: URL? {
        state.withLock { $0.source }
    }

    var movedDestination: URL? {
        state.withLock { $0.destination }
    }

    var removedURL: URL? {
        state.withLock { $0.removed }
    }

    func recordMove(source: URL, destination: URL) {
        state.withLock {
            $0.source = source
            $0.destination = destination
        }
    }

    func recordRemoval(_ url: URL) {
        state.withLock { $0.removed = url }
    }
}
