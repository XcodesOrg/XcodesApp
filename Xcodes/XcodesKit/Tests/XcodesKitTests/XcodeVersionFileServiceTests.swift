@preconcurrency import Path
import Version
import XCTest
@testable import XcodesKit

final class XcodeVersionFileServiceTests: XCTestCase {
    private let projectPath = Path("/tmp/project")!

    func testVersionParsesGemVersionFile() {
        let service = XcodeVersionFileService(
            fileExists: { path in path.hasSuffix(".xcode-version") },
            contentsAtPath: { _ in "9.2b3".data(using: .utf8) }
        )

        XCTAssertEqual(
            service.version(inDirectory: projectPath),
            Version("9.2.0-Beta.3")
        )
    }

    func testVersionReturnsNilWhenFileDoesNotExist() {
        let service = XcodeVersionFileService(
            fileExists: { _ in false },
            contentsAtPath: { _ in XCTFail("Should not read a missing file"); return nil }
        )

        XCTAssertNil(service.version(inDirectory: projectPath))
    }

    func testVersionReturnsNilWhenFileContentsAreInvalid() {
        let service = XcodeVersionFileService(
            fileExists: { _ in true },
            contentsAtPath: { _ in Data([0xff]) }
        )

        XCTAssertNil(service.version(inDirectory: projectPath))
    }
}
