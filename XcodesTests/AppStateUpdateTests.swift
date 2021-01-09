import Path
import Version
@testable import Xcodes
import XCTest

class AppStateUpdateTests: XCTestCase {
    var subject: AppState!
    
    override func setUpWithError() throws {
        Current = .mock
        subject = AppState()
    }

    func testDoesNotReplaceInstallState() throws {
        subject.allXcodes = [
            Xcode(version: Version("0.0.0")!, installState: .installing(.unarchiving), selected: false, path: nil, icon: nil)
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].installState, .installing(.unarchiving))
    }
}
