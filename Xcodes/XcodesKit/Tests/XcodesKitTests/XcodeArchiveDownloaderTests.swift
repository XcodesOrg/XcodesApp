import XCTest
@testable import XcodesKit

final class XcodeArchiveDownloaderTests: XCTestCase {
    func testRawValuesMatchPersistedPreferenceValues() {
        XCTAssertEqual(XcodeArchiveDownloader.aria2.rawValue, "aria2")
        XCTAssertEqual(XcodeArchiveDownloader.urlSession.rawValue, "urlSession")
    }

    func testDescriptionUsesAppDisplayNames() {
        XCTAssertEqual(XcodeArchiveDownloader.aria2.description, "aria2")
        XCTAssertEqual(XcodeArchiveDownloader.urlSession.description, "URLSession")
    }
}
