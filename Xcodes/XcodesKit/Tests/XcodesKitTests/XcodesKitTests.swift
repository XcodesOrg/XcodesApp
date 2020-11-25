import XCTest
@testable import XcodesKit

final class XcodesKitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(XcodesKit().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
