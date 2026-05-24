import XCTest
@testable import XcodesKit

final class SDKsTests: XCTestCase {
    func testAllBuildsReturnsBuildsAcrossAllPlatformsInAppOrder() {
        let sdks = SDKs(
            macOS: [XcodeVersion("24A335")],
            iOS: [XcodeVersion("22A336"), XcodeVersion(number: "18.0")],
            watchOS: [XcodeVersion("22R349")],
            tvOS: [XcodeVersion("22J357")],
            visionOS: [XcodeVersion("22N320")]
        )

        XCTAssertEqual(sdks.allBuilds, [
            "22A336",
            "22J357",
            "24A335",
            "22R349",
            "22N320",
        ])
    }

    func testAllBuildsSkipsMissingPlatformAndBuildValues() {
        let sdks = SDKs(
            macOS: nil,
            iOS: [XcodeVersion(number: "18.0")],
            watchOS: nil,
            tvOS: [XcodeVersion("22J357")],
            visionOS: nil
        )

        XCTAssertEqual(sdks.allBuilds, ["22J357"])
    }
}
