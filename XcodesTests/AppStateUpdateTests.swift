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
    
    func testRemovesUninstalledVersion() throws {
        subject.allXcodes = [
            Xcode(version: Version("0.0.0")!, installState: .installed, selected: true, path: "/Applications/Xcode-0.0.0.app", icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil))
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].installState, .notInstalled)
    }
    
    func testDeterminesIfInstalledByBuildMetadataAlone() throws {
        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                // Note "GM" prerelease identifier
                AvailableXcode(version: Version("0.0.0-GM+ABC123")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
            ], 
            installedXcodes: [
                InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].version, Version("0.0.0+ABC123")!) 
        XCTAssertEqual(subject.allXcodes[0].installState, .installed)
        XCTAssertEqual(subject.allXcodes[0].selected, false)
        XCTAssertEqual(subject.allXcodes[0].path, "/Applications/Xcode-0.0.0.app")
    }
}
