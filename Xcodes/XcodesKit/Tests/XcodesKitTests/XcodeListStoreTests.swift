import XCTest
@preconcurrency import Path
import Version
import os
@testable import XcodesKit

final class XcodeListStoreTests: XCTestCase {
    func testLoadsCachedXcodesAndUsesCacheDateForUpdatePolicy() throws {
        let xcode = try makeXcode(version: "15.0.0")
        let cacheDate = Date(timeIntervalSince1970: 1_000)
        let cache = AvailableXcodeCache(
            cacheFile: try XCTUnwrap(Path("/tmp/xcodes.json")),
            contentsAtPath: { _ in try? JSONEncoder().encode([xcode]) },
            attributesOfItem: { _ in [.modificationDate: cacheDate] }
        )
        var store = XcodeListStore(
            cache: cache,
            fetchAvailableXcodes: { _ in [] },
            updatePolicy: XcodeUpdatePolicy(now: { cacheDate.addingTimeInterval(60) })
        )

        try store.loadCachedAvailableXcodes()

        XCTAssertEqual(store.availableXcodes, [xcode])
        XCTAssertEqual(store.lastUpdated, cacheDate)
        XCTAssertFalse(store.shouldUpdateBeforeListingVersions)
    }

    func testMissingCacheNeedsUpdate() throws {
        let cache = AvailableXcodeCache(
            cacheFile: try XCTUnwrap(Path("/tmp/xcodes.json")),
            contentsAtPath: { _ in nil }
        )
        var store = XcodeListStore(cache: cache, fetchAvailableXcodes: { _ in [] })

        try store.loadCachedAvailableXcodes()

        XCTAssertTrue(store.shouldUpdateBeforeListingVersions)
    }

    func testUpdateFetchesPostprocessesAndSavesXcodes() async throws {
        let release = try makeRelease(version: "15.0.0-beta.1+15A1", architectures: nil)
        let finalRelease = try makeRelease(version: "15.0.0+15A1", architectures: nil)
        let expected = try makeXcode(version: "15.0.0+15A1")
        let updateDate = Date(timeIntervalSince1970: 2_000)
        let savedXcodes = XcodeCacheSaveRecorder()
        let cache = AvailableXcodeCache(
            cacheFile: try XCTUnwrap(Path("/tmp/xcodes.json")),
            contentsAtPath: { _ in nil },
            writeData: { data, _ in
                try savedXcodes.record(data)
            },
            createDirectory: { _, _, _ in }
        )
        var store = XcodeListStore(
            cache: cache,
            fetchAvailableXcodes: { dataSource in
                XCTAssertEqual(dataSource, .xcodeReleases)
                return [release, finalRelease]
            },
            now: { updateDate }
        )

        let xcodes = try await store.updateAvailableXcodes(from: .xcodeReleases)

        XCTAssertEqual(xcodes, [expected])
        XCTAssertEqual(store.availableXcodes, [expected])
        XCTAssertEqual(store.lastUpdated, updateDate)
        XCTAssertEqual(savedXcodes.value, [expected])
    }

    private func makeXcode(version: String, architectures: [Architecture]? = nil) throws -> AvailableXcode {
        AvailableXcode(
            version: try XCTUnwrap(Version(version)),
            url: try XCTUnwrap(URL(string: "https://example.com/Xcode.xip")),
            filename: "Xcode.xip",
            releaseDate: nil,
            architectures: architectures
        )
    }

    private func makeRelease(version: String, architectures: [Architecture]?) throws -> AvailableXcodeRelease {
        AvailableXcodeRelease(
            version: try XCTUnwrap(Version(version)),
            url: try XCTUnwrap(URL(string: "https://example.com/Xcode.xip")),
            filename: "Xcode.xip",
            releaseDate: nil,
            architectures: architectures
        )
    }
}

private final class XcodeCacheSaveRecorder: Sendable {
    private let storedValue = OSAllocatedUnfairLock<[AvailableXcode]?>(initialState: nil)

    var value: [AvailableXcode]? {
        storedValue.withLock { $0 }
    }

    func record(_ data: Data) throws {
        let value = try JSONDecoder().decode([AvailableXcode].self, from: data)
        storedValue.withLock { $0 = value }
    }
}
