import XCTest
@preconcurrency import Path
@testable import XcodesKit

final class XcodesPathResolverTests: XCTestCase {
    func testAppApplicationSupportUsesSavedPathWhenValid() throws {
        let path = try XCTUnwrap(Path("/tmp/custom-xcodes-support"))

        XCTAssertEqual(
            XcodesPathResolver.appApplicationSupport(savedPath: path.string),
            path
        )
    }

    func testAppApplicationSupportFallsBackToAppDefault() {
        XCTAssertEqual(
            XcodesPathResolver.appApplicationSupport(savedPath: nil),
            XcodesPathResolver.appDefaultApplicationSupport
        )
    }

    func testAppInstallDirectoryUsesSavedPathWhenValid() throws {
        let path = try XCTUnwrap(Path("/tmp/Xcodes"))

        XCTAssertEqual(
            XcodesPathResolver.appInstallDirectory(savedPath: path.string),
            path
        )
    }

    func testAppInstallDirectoryFallsBackToAppDefault() {
        XCTAssertEqual(
            XcodesPathResolver.appInstallDirectory(savedPath: nil),
            XcodesPathResolver.appDefaultInstallDirectory
        )
    }

    func testCacheFilePathsAreDerivedFromApplicationSupport() throws {
        let supportPath = try XCTUnwrap(Path("/tmp/xcodes-support"))

        XCTAssertEqual(
            XcodesPathResolver.availableXcodesCacheFile(in: supportPath),
            supportPath/"available-xcodes.json"
        )
        XCTAssertEqual(
            XcodesPathResolver.downloadableRuntimesCacheFile(in: supportPath),
            supportPath/"downloadable-runtimes.json"
        )
    }

    func testCLIPathsAreDerivedFromEnvironmentHome() throws {
        let home = try XCTUnwrap(Path("/Users/example"))

        XCTAssertEqual(
            XcodesPathResolver.cliHome(environment: ["HOME": home.string]),
            home
        )
        XCTAssertEqual(
            XcodesPathResolver.cliApplicationSupport(home: home),
            home/"Library/Application Support/com.robotsandpencils.xcodes"
        )
        XCTAssertEqual(
            XcodesPathResolver.cliOldApplicationSupport(home: home),
            home/"Library/Application Support/ca.brandonevans.xcodes"
        )
        XCTAssertEqual(
            XcodesPathResolver.cliCaches(home: home),
            home/"Library/Caches/com.robotsandpencils.xcodes"
        )
        XCTAssertEqual(
            XcodesPathResolver.cliDownloads(home: home),
            home/"Downloads"
        )
    }

    func testCLIConfigurationFileIsDerivedFromApplicationSupport() throws {
        let supportPath = try XCTUnwrap(Path("/tmp/xcodes-support"))

        XCTAssertEqual(
            XcodesPathResolver.cliAvailableXcodesCacheFile(applicationSupport: supportPath),
            supportPath/"available-xcodes.json"
        )
        XCTAssertEqual(
            XcodesPathResolver.cliConfigurationFile(applicationSupport: supportPath),
            supportPath/"configuration.json"
        )
    }
}
