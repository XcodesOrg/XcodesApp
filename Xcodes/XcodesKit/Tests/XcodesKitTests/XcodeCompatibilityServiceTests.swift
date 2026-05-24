import Foundation
import Version
import XCTest
@testable import XcodesKit

final class XcodeCompatibilityServiceTests: XCTestCase {
    func testNilRequiredVersionIsSupported() {
        XCTAssertTrue(
            XcodeCompatibilityService().isSupported(
                requiredMacOSVersion: nil,
                currentOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
            )
        )
    }

    func testCurrentVersionEqualToRequiredVersionIsSupported() {
        XCTAssertTrue(
            XcodeCompatibilityService().isSupported(
                requiredMacOSVersion: "14.1.2",
                currentOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 2)
            )
        )
    }

    func testCurrentVersionNewerThanRequiredVersionIsSupported() {
        XCTAssertTrue(
            XcodeCompatibilityService().isSupported(
                requiredMacOSVersion: "14.1.2",
                currentOSVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            )
        )
    }

    func testCurrentVersionOlderThanRequiredVersionIsUnsupported() {
        XCTAssertTrue(
            XcodeCompatibilityService().isUnsupported(
                requiredMacOSVersion: "14.1.2",
                currentOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 1)
            )
        )
    }

    func testStatusIncludesRequiredAndCurrentVersionsWhenUnsupported() {
        XCTAssertEqual(
            XcodeCompatibilityService().status(
                requiredMacOSVersion: "14.1.2",
                currentOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 1)
            ),
            .unsupported(requiredMacOSVersion: "14.1.2", currentMacOSVersion: "14.1.1")
        )
    }

    func testStatusForXcodeUsesRequiredMacOSVersion() {
        let xcode = AvailableXcode(
            version: Version("16.0.0")!,
            url: URL(fileURLWithPath: "/Xcode.xip"),
            filename: "Xcode.xip",
            releaseDate: nil,
            requiredMacOSVersion: "15.0"
        )

        XCTAssertEqual(
            XcodeCompatibilityService().status(
                for: xcode,
                currentOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)
            ),
            .unsupported(requiredMacOSVersion: "15.0", currentMacOSVersion: "14.6.0")
        )
    }

    func testMissingMinorAndPatchDefaultToZero() {
        let version = XcodeCompatibilityService().operatingSystemVersion(from: "14")

        XCTAssertEqual(version.majorVersion, 14)
        XCTAssertEqual(version.minorVersion, 0)
        XCTAssertEqual(version.patchVersion, 0)
    }

    func testInvalidVersionComponentsDefaultToZero() {
        let version = XcodeCompatibilityService().operatingSystemVersion(from: "14.beta.2")

        XCTAssertEqual(version.majorVersion, 14)
        XCTAssertEqual(version.minorVersion, 2)
        XCTAssertEqual(version.patchVersion, 0)
    }
}
