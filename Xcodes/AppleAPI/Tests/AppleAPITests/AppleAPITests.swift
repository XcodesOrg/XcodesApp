import XCTest
@testable import AppleAPI

final class AppleAPITests: XCTestCase {
    
    func testValidHashCashMint() {
        let bits: UInt = 11
        let resource = "4d74fb15eb23f465f1f6fcbf534e5877"
        let testDate = "20230223170600"
 
        let stamp = Hashcash().mint(resource: resource, bits: bits, date: testDate)
        XCTAssertEqual(stamp, "1:11:20230223170600:4d74fb15eb23f465f1f6fcbf534e5877::6373")
    }
    func testValidHashCashMint2() {
        let bits: UInt = 10
        let resource = "bb63edf88d2f9c39f23eb4d6f0281158"
        let testDate = "20230224001754"
 
        let stamp = Hashcash().mint(resource: resource, bits: bits, date: testDate)
        XCTAssertEqual(stamp, "1:10:20230224001754:bb63edf88d2f9c39f23eb4d6f0281158::866")
    }

    static var allTests = [
        ("testValidHashCashMint", testValidHashCashMint),
        ("testValidHashCashMint2", testValidHashCashMint2),
    ]
}
