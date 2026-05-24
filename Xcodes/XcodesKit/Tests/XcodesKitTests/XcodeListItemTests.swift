import XCTest
@preconcurrency import Path
import Version
@testable import XcodesKit

final class XcodeListItemTests: XCTestCase {
    func testInstalledPathReturnsPathFromInstallState() throws {
        let path = try XCTUnwrap(Path("/Applications/Xcode.app"))
        let item = XcodeListItem(
            version: try XCTUnwrap(Version("15.0.0")),
            installState: .installed(path),
            selected: true
        )

        XCTAssertEqual(item.installedPath, path)
        XCTAssertEqual(item.installState.installedPath, path)
    }

    func testInstalledPathReturnsNilWhenNotInstalled() throws {
        let item = XcodeListItem(
            version: try XCTUnwrap(Version("15.0.0")),
            installState: .notInstalled,
            selected: false
        )

        XCTAssertNil(item.installedPath)
        XCTAssertNil(item.installState.installedPath)
    }

    func testDownloadFileSizeStringFormatsFileSize() throws {
        let item = XcodeListItem(
            version: try XCTUnwrap(Version("15.0.0")),
            installState: .notInstalled,
            selected: false,
            downloadFileSize: 1_500_000_000
        )

        XCTAssertEqual(
            item.downloadFileSizeString,
            ByteCountFormatter.string(fromByteCount: 1_500_000_000, countStyle: .file)
        )
    }

    func testDownloadFileSizeStringReturnsNilWhenMissing() throws {
        let item = XcodeListItem(
            version: try XCTUnwrap(Version("15.0.0")),
            installState: .notInstalled,
            selected: false
        )

        XCTAssertNil(item.downloadFileSizeString)
    }
}
