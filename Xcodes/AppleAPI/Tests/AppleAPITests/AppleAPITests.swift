import XCTest
@testable import AppleAPI

final class AppleAPITests: XCTestCase {
    
    func testValidHashCashMint() {
        let bits: UInt = 10
        let resource = "bb63edf88d2f9c39f23eb4d6f0281158"
        let testDate = "20230224001754"
        
//    "1:11:20230224004345:8982e236688f6ebf588c4bd4b445c4cc::877"
//        7395f792caf430dca2d07ae7be0c63fa
        
        let stamp = Hashcash().mint(resource: resource, bits: bits, date: testDate)
        XCTAssertNotNil(stamp)
        XCTAssertEqual(stamp, "1:10:20230224001754:bb63edf88d2f9c39f23eb4d6f0281158::866")
        
        print(stamp)
    }

    static var allTests = [
        ("testValidHashCashMint", testValidHashCashMint),
    ]
}
