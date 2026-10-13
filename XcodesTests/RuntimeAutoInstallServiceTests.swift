import XcodesKit
@testable import Xcodes
import XCTest

class RuntimeAutoInstallServiceTests: XCTestCase {
    let subject = RuntimeAutoInstallService()

    // MARK: - Choosing runtimes

    func test_noSelectedPlatforms_installsNothing() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
            ],
            installedRuntimes: [],
            includingPrereleases: false
        )

        XCTAssertTrue(runtimes.isEmpty)
    }

    func test_installsOnlyTheNewestRuntimeOfEachSelectedPlatform() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.watchOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .watchOS, version: "10.5", buildUpdate: "21T576"),
                try makeRuntime(platform: .watchOS, version: "11.4", buildUpdate: "22T249"),
                try makeRuntime(platform: .watchOS, version: "9.4", buildUpdate: "20T253"),
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
            ],
            installedRuntimes: [],
            includingPrereleases: false
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["watchOS 11.4"])
    }

    func test_comparesRuntimesByVersionAndNotByString() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A339"),
            ],
            installedRuntimes: [],
            includingPrereleases: false
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 26.0"])
    }

    func test_returnsOneRuntimePerPlatformInPresentationOrder() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.visionOS, .iOS, .watchOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .watchOS, version: "11.4", buildUpdate: "22T249"),
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
                try makeRuntime(platform: .visionOS, version: "2.4", buildUpdate: "22O233"),
                try makeRuntime(platform: .tvOS, version: "18.4", buildUpdate: "22L251"),
            ],
            installedRuntimes: [],
            includingPrereleases: false
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 18.5", "watchOS 11.4", "visionOS 2.4"])
    }

    func test_skipsPlatformsWhoseNewestRuntimeIsAlreadyInstalled() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS, .watchOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
                try makeRuntime(platform: .watchOS, version: "11.4", buildUpdate: "22T249"),
            ],
            installedRuntimes: [makeInstalledRuntime(build: "22F77")],
            includingPrereleases: false
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["watchOS 11.4"])
    }

    func test_installsANewerRuntimeEvenWhenAnOlderOneIsInstalled() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.4", buildUpdate: "22E238"),
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
            ],
            installedRuntimes: [makeInstalledRuntime(build: "22E238")],
            includingPrereleases: false
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 18.5"])
    }

    func test_installsNothingWhenAPlatformHasNoDownloadableRuntimes() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.tvOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
            ],
            installedRuntimes: [],
            includingPrereleases: false
        )

        XCTAssertTrue(runtimes.isEmpty)
    }

    // MARK: - Prereleases

    func test_ignoresBetaRuntimesByDefault() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A5260", seedNumber: 2),
            ],
            installedRuntimes: [],
            includingPrereleases: false
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 18.5"])
    }

    func test_installsBetaRuntimesWhenPrereleasesAreIncluded() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "18.5", buildUpdate: "22F77"),
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A5260", seedNumber: 2),
            ],
            installedRuntimes: [],
            includingPrereleases: true
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 26.0-beta2"])
    }

    func test_prefersTheReleaseOverABetaOfTheSameVersion() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A5260", seedNumber: 2),
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A339"),
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A5297", seedNumber: 4),
            ],
            installedRuntimes: [],
            includingPrereleases: true
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 26.0"])
    }

    func test_prefersTheHighestSeedWhenOnlyBetasAreAvailable() throws {
        let runtimes = subject.runtimesToInstall(
            platforms: [.iOS],
            downloadableRuntimes: [
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A5260", seedNumber: 2),
                try makeRuntime(platform: .iOS, version: "26.0", buildUpdate: "23A5297", seedNumber: 4),
            ],
            installedRuntimes: [],
            includingPrereleases: true
        )

        XCTAssertEqual(runtimes.map(\.visibleIdentifier), ["iOS 26.0-beta4"])
    }

    // MARK: - Preference storage

    func test_platformPreferenceRoundTrips() {
        let preference = AutoInstallRuntimePlatforms(platforms: [.watchOS, .iOS])

        XCTAssertEqual(preference.rawValue, "com.apple.platform.iphoneos,com.apple.platform.watchos")
        XCTAssertEqual(AutoInstallRuntimePlatforms(rawValue: preference.rawValue), preference)
    }

    func test_emptyPlatformPreferenceRoundTrips() {
        let preference = AutoInstallRuntimePlatforms()

        XCTAssertEqual(preference.rawValue, "")
        XCTAssertEqual(AutoInstallRuntimePlatforms(rawValue: ""), preference)
    }

    func test_platformPreferenceIgnoresUnknownIdentifiers() {
        let preference = AutoInstallRuntimePlatforms(rawValue: "com.apple.platform.watchos,com.apple.platform.toaster")

        XCTAssertEqual(preference?.platforms, [.watchOS])
    }

    func test_settingAPlatformOnAndOff() {
        var preference = AutoInstallRuntimePlatforms()

        preference.setContains(true, for: .tvOS)
        XCTAssertTrue(preference.contains(.tvOS))

        preference.setContains(false, for: .tvOS)
        XCTAssertFalse(preference.contains(.tvOS))
    }

    // MARK: - Helpers

    /// `DownloadableRuntime` is only `Decodable`, so build one the way the app does.
    private func makeRuntime(
        platform: DownloadableRuntime.Platform,
        version: String,
        buildUpdate: String,
        seedNumber: Int? = nil
    ) throws -> DownloadableRuntime {
        var json: [String: Any] = [
            "category": "simulator",
            "simulatorVersion": ["buildUpdate": buildUpdate, "version": version],
            "dictionaryVersion": 2,
            "contentType": "diskImage",
            "platform": platform.rawValue,
            "identifier": "com.apple.dmg.\(platform.shortName).\(buildUpdate)",
            "version": "\(version) (\(buildUpdate))",
            "fileSize": 7_000_000_000,
            "name": "\(platform.shortName) \(version)",
        ]
        if let seedNumber {
            json["seedNumber"] = seedNumber
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(DownloadableRuntime.self, from: data)
    }

    private func makeInstalledRuntime(build: String) -> CoreSimulatorImage {
        CoreSimulatorImage(
            uuid: build,
            path: ["relative": "file:///Library/Developer/CoreSimulator/Images/\(build).dmg"],
            runtimeInfo: CoreSimulatorRuntimeInfo(build: build)
        )
    }
}
