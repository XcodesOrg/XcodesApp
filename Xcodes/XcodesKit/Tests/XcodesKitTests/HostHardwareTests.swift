import XCTest
@testable import XcodesKit

final class HostHardwareTests: XCTestCase {
    func testIsAppleSiliconReturnsTrueForArm64() {
        XCTAssertTrue(HostHardware.isAppleSilicon(machineHardwareName: "arm64"))
    }

    func testIsAppleSiliconReturnsFalseForIntel() {
        XCTAssertFalse(HostHardware.isAppleSilicon(machineHardwareName: "x86_64"))
    }

    func testIsAppleSiliconReturnsFalseForUnknownHardware() {
        XCTAssertFalse(HostHardware.isAppleSilicon(machineHardwareName: nil))
    }
}
