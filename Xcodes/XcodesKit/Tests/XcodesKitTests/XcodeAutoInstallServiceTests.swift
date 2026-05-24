@preconcurrency import Path
import Version
import XCTest
@testable import XcodesKit

final class XcodeAutoInstallServiceTests: XCTestCase {
    func testDecisionIsDisabledWhenAutoInstallIsOff() {
        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: .none,
            xcodes: [
                xcode(version: "15.0.0", installState: .notInstalled)
            ]
        )

        XCTAssertEqual(decision, .disabled)
    }

    func testDecisionIsAlreadyInstalledWhenNewestXcodeIsInstalled() {
        let path = Path("/Applications/Xcode-15.0.app")!
        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: .newestVersion,
            xcodes: [
                xcode(version: "15.0.0", installState: .installed(path))
            ]
        )

        XCTAssertEqual(decision, .alreadyInstalled)
    }

    func testDecisionInstallsNewestBetaForNewestBetaPreference() {
        let newestXcode = xcode(version: "16.0.0-beta.1", installState: .notInstalled)
        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: .newestBeta,
            xcodes: [newestXcode]
        )

        XCTAssertEqual(decision, .installNewestBeta(newestXcode.id))
    }

    func testDecisionInstallsNewestReleaseForNewestVersionPreference() {
        let newestXcode = xcode(version: "15.0.0", installState: .notInstalled)
        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: .newestVersion,
            xcodes: [newestXcode]
        )

        XCTAssertEqual(decision, .installNewestVersion(newestXcode.id))
    }

    func testDecisionDoesNotInstallPrereleaseForNewestVersionPreference() {
        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: .newestVersion,
            xcodes: [
                xcode(version: "16.0.0-beta.1", installState: .notInstalled)
            ]
        )

        XCTAssertEqual(decision, .noNewVersion)
    }

    func testDecisionIsAlreadyInstalledWhenNoXcodesAreAvailable() {
        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: .newestVersion,
            xcodes: []
        )

        XCTAssertEqual(decision, .alreadyInstalled)
    }

    private func xcode(version: String, installState: XcodeInstallState) -> XcodeListItem {
        XcodeListItem(
            version: Version(version)!,
            installState: installState,
            selected: false
        )
    }
}
