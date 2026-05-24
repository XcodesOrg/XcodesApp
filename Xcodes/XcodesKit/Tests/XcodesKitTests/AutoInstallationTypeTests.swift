import XCTest
@testable import XcodesKit

final class AutoInstallationTypeTests: XCTestCase {
    func testAutoInstallingSetterEnablesNewestVersion() {
        var type = AutoInstallationType.none

        type.isAutoInstalling = true

        XCTAssertEqual(type, .newestVersion)
    }

    func testAutoInstallingSetterDisablesInstallation() {
        var type = AutoInstallationType.newestBeta

        type.isAutoInstalling = false

        XCTAssertEqual(type, .none)
    }

    func testAutoInstallingBetaSetterPreservesEnabledReleaseStateWhenDisabled() {
        var type = AutoInstallationType.newestVersion

        type.isAutoInstallingBeta = false

        XCTAssertEqual(type, .newestVersion)
    }

    func testAutoInstallingBetaSetterEnablesNewestBeta() {
        var type = AutoInstallationType.none

        type.isAutoInstallingBeta = true

        XCTAssertEqual(type, .newestBeta)
    }
}
