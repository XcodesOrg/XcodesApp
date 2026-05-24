import XCTest
@preconcurrency import Path
import os
@testable import XcodesKit

final class RuntimeListStoreTests: XCTestCase {
    func testLoadsCachedDownloadableRuntimes() throws {
        let runtime = Self.downloadableRuntime(buildUpdate: "20A360")
        let cache = DownloadableRuntimeCache(
            cacheFile: try XCTUnwrap(Path("/tmp/downloadable-runtimes.json")),
            contentsAtPath: { _ in try? JSONEncoder().encode([runtime]) }
        )
        var store = RuntimeListStore(cache: cache, fetchDownloadableRuntimes: {
            XCTFail("Cache load should not fetch runtimes")
            return Self.downloadableResponse(downloadables: [])
        })

        try store.loadCachedDownloadableRuntimes()

        XCTAssertEqual(store.downloadableRuntimes, [runtime])
    }

    func testUpdateFetchesAddsSDKBuildUpdatesAndSavesRuntimes() async throws {
        let runtime = Self.downloadableRuntime(buildUpdate: "20A360")
        let response = Self.downloadableResponse(
            downloadables: [runtime],
            sdkToSimulatorMappings: [
                SDKToSimulatorMapping(
                    sdkBuildUpdate: "20A361",
                    simulatorBuildUpdate: "20A360",
                    sdkIdentifier: "com.apple.platform.iphonesimulator",
                    downloadableIdentifiers: nil
                )
            ]
        )
        let savedRuntimes = RuntimeCacheSaveRecorder()
        let cache = DownloadableRuntimeCache(
            cacheFile: try XCTUnwrap(Path("/tmp/downloadable-runtimes.json")),
            contentsAtPath: { _ in nil },
            writeData: { data, _ in
                try savedRuntimes.record(data)
            },
            createDirectory: { _, _, _ in }
        )
        var store = RuntimeListStore(cache: cache, fetchDownloadableRuntimes: { response })

        let runtimes = try await store.updateDownloadableRuntimes()

        XCTAssertEqual(runtimes.map(\.sdkBuildUpdate), [["20A361"]])
        XCTAssertEqual(store.downloadableRuntimes, runtimes)
        XCTAssertEqual(savedRuntimes.value, runtimes)
    }

    private static func downloadableRuntime(buildUpdate: String) -> DownloadableRuntime {
        DownloadableRuntime(
            category: .simulator,
            simulatorVersion: .init(buildUpdate: buildUpdate, version: "16.0"),
            source: "https://example.com/iOS.dmg",
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

    private static func downloadableResponse(
        downloadables: [DownloadableRuntime],
        sdkToSimulatorMappings: [SDKToSimulatorMapping] = []
    ) -> DownloadableRuntimesResponse {
        DownloadableRuntimesResponse(
            sdkToSimulatorMappings: sdkToSimulatorMappings,
            sdkToSeedMappings: [],
            refreshInterval: 0,
            downloadables: downloadables,
            version: "1"
        )
    }
}

private final class RuntimeCacheSaveRecorder: Sendable {
    private let storedValue = OSAllocatedUnfairLock<[DownloadableRuntime]?>(initialState: nil)

    var value: [DownloadableRuntime]? {
        storedValue.withLock { $0 }
    }

    func record(_ data: Data) throws {
        let value = try JSONDecoder().decode([DownloadableRuntime].self, from: data)
        storedValue.withLock { $0 = value }
    }
}
