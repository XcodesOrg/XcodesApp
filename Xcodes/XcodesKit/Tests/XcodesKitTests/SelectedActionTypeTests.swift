import XCTest
@testable import XcodesKit

final class SelectedActionTypeTests: XCTestCase {
    func testRawValuesMatchStoredPreferenceValues() {
        XCTAssertEqual(SelectedActionType.none.rawValue, "none")
        XCTAssertEqual(SelectedActionType.rename.rawValue, "rename")
    }

    func testDefaultDoesNothing() {
        XCTAssertEqual(SelectedActionType.default, .none)
    }
}
