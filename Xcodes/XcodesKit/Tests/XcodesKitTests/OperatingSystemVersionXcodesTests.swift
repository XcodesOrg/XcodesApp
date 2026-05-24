import XCTest
@testable import XcodesKit

final class OperatingSystemVersionXcodesTests: XCTestCase {
    func testVersionStringIncludesMajorMinorAndPatchVersions() {
        let version = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)

        XCTAssertEqual(version.versionString(), "14.6.1")
    }
}
