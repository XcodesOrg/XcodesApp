import XCTest
import Version
@testable import XcodesKit

final class VersionMatchingTests: XCTestCase {
    private struct Candidate: Equatable {
        let version: Version
        let name: String
    }

    func testFindXcodePrefersEquivalentMatch() {
        let candidates = [
            Candidate(version: Version("15.0.0+AAA")!, name: "release"),
            Candidate(version: Version("15.0.0-beta+BBB")!, name: "beta")
        ]

        XCTAssertEqual(
            XcodeVersionMatcher.find(version: Version("15.0.0-beta")!, in: candidates, versionKeyPath: \.version),
            Candidate(version: Version("15.0.0-beta+BBB")!, name: "beta")
        )
    }

    func testFindXcodeFallsBackToSingleVersionMatchWithoutIdentifiers() {
        let candidates = [
            Candidate(version: Version("15.0.0-rc+AAA")!, name: "rc")
        ]

        XCTAssertEqual(
            XcodeVersionMatcher.find(version: Version("15.0.0")!, in: candidates, versionKeyPath: \.version),
            Candidate(version: Version("15.0.0-rc+AAA")!, name: "rc")
        )
    }

    func testFindXcodeRejectsAmbiguousFallbackMatches() {
        let candidates = [
            Candidate(version: Version("15.0.0-beta+AAA")!, name: "beta"),
            Candidate(version: Version("15.0.0-rc+BBB")!, name: "rc")
        ]

        XCTAssertNil(XcodeVersionMatcher.find(version: Version("15.0.0")!, in: candidates, versionKeyPath: \.version))
    }
}
