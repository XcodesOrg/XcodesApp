@preconcurrency import Path
import XCTest
import os
@testable import XcodesKit

final class CodableFileStoreTests: XCTestCase {
    private struct Fixture: Codable, Equatable {
        var name: String
    }

    private let file = Path("/tmp/configuration.json")!

    func testLoadReturnsNilWhenFileIsMissing() throws {
        let store = CodableFileStore<Fixture>(
            contentsAtPath: { _ in nil }
        )

        XCTAssertNil(try store.load(from: file))
    }

    func testLoadDecodesValueFromFile() throws {
        let data = try JSONEncoder().encode(Fixture(name: "Xcodes"))
        let store = CodableFileStore<Fixture>(
            contentsAtPath: { _ in data }
        )

        XCTAssertEqual(try store.load(from: file), Fixture(name: "Xcodes"))
    }

    func testLoadThrowsDecodeErrorForInvalidFile() {
        let store = CodableFileStore<Fixture>(
            contentsAtPath: { _ in Data("not json".utf8) }
        )

        XCTAssertThrowsError(try store.load(from: file))
    }

    func testSaveCreatesParentDirectoryAndWritesEncodedValue() throws {
        let recorder = CodableFileStoreRecorder()

        let store = CodableFileStore<Fixture>(
            createDirectory: { url, createIntermediates, _ in
                recorder.recordDirectory(url, createIntermediates: createIntermediates)
            },
            createFile: { path, data, _ in
                recorder.recordFile(path: path, data: data)
                return true
            }
        )

        try store.save(Fixture(name: "Xcodes"), to: file)

        XCTAssertEqual(recorder.createdDirectory, file.url.deletingLastPathComponent())
        XCTAssertEqual(recorder.createdIntermediates, true)
        XCTAssertEqual(recorder.writtenPath, file.string)
        XCTAssertEqual(try JSONDecoder().decode(Fixture.self, from: XCTUnwrap(recorder.writtenData)), Fixture(name: "Xcodes"))
    }
}

private final class CodableFileStoreRecorder: Sendable {
    private struct State: Sendable {
        var directory: URL?
        var createIntermediates: Bool?
        var path: String?
        var data: Data?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var createdDirectory: URL? {
        state.withLock { $0.directory }
    }

    var createdIntermediates: Bool? {
        state.withLock { $0.createIntermediates }
    }

    var writtenPath: String? {
        state.withLock { $0.path }
    }

    var writtenData: Data? {
        state.withLock { $0.data }
    }

    func recordDirectory(_ url: URL, createIntermediates: Bool) {
        state.withLock {
            $0.directory = url
            $0.createIntermediates = createIntermediates
        }
    }

    func recordFile(path: String, data: Data?) {
        state.withLock {
            $0.path = path
            $0.data = data
        }
    }
}
