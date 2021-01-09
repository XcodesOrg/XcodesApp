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
            Xcode(version: Version("0.0.0")!, installState: .installing(.unarchiving), selected: false, icon: nil)
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
            Xcode(version: Version("0.0.0")!, installState: .installed(Path("/Applications/Xcode-0.0.0.app")!), selected: true, icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil))
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
        XCTAssertEqual(subject.allXcodes[0].installState, .installed(Path("/Applications/Xcode-0.0.0.app")!))
        XCTAssertEqual(subject.allXcodes[0].selected, false)
    }
    
    func testAdjustedVersionsAreUsedToLookupAvailableXcode() throws {
        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                // Note "GM" prerelease identifier
                AvailableXcode(version: Version("0.0.0-GM+ABC123")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil, sdks: .init(iOS: .init("14.3")))
            ], 
            installedXcodes: [
                InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes[0].version, Version("0.0.0+ABC123")!) 
        XCTAssertEqual(subject.allXcodes[0].installState, .installed(Path("/Applications/Xcode-0.0.0.app")!))
        XCTAssertEqual(subject.allXcodes[0].selected, false)
        // XCModel types aren't equatable, so just check for non-nil for now
        XCTAssertNotNil(subject.allXcodes[0].sdks)
    }

    func testAppendingInstalledVersionThatIsNotAvailable() {
        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("1.2.3")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil, sdks: .init(iOS: .init("14.3")))
            ], 
            installedXcodes: [
                // There's a version installed which for some reason isn't listed online
                InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("1.2.3")!, Version("0.0.0+ABC123")!]) 
    }
    
    func testFilterReleasesThatMatchPrereleases() {
        let result = subject.filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers(
            [
                AvailableXcode(version: Version("12.3.0+12C33")!, url: URL(string: "https://apple.com")!, filename: "Xcode_12.3.xip", releaseDate: nil),
                AvailableXcode(version: Version("12.3.0-RC+12C33")!, url: URL(string: "https://apple.com")!, filename: "Xcode_12.3_RC_1.xip", releaseDate: nil),
            ]
        )
        XCTAssertEqual(result.map(\.version), [Version("12.3.0+12C33")])
    }
}
