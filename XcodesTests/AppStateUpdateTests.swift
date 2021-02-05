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
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "apple" 
            } else {
                return nil
            }
        }
        
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
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "apple" 
            } else {
                return nil
            }
        }

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
    
    
    func testIdenticalBuilds_KeepsReleaseVersion_WithNeitherInstalled() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "xcodeReleases" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("12.4.0+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("12.4.0-RC+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("12.4.0+12D4e")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[Version("12.4.0+12D4e")!, Version("12.4.0-RC+12D4e")!]])
    }
    
    func testIdenticalBuilds_DoNotMergeReleaseVersions() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "xcodeReleases" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("3.2.3+10M2262")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("3.2.3+10M2262")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("3.2.3+10M2262")!, Version("3.2.3+10M2262")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[], []])
    }
    
    func testIdenticalBuilds_KeepsReleaseVersion_WithPrereleaseInstalled() {
        Current.defaults.string = { key in
            if key == "dataSource" {
                return "xcodeReleases" 
            } else {
                return nil
            }
        }

        subject.allXcodes = [
        ]
        
        Current.files.contentsAtPath = { path in
            if path.contains("Info.plist") {
                return """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0">
                    <dict>
                        <key>CFBundleIdentifier</key>
                        <string>com.apple.dt.Xcode</string>
                        <key>CFBundleShortVersionString</key>
                        <string>12.4.0</string>
                    </dict>
                    </plist>
                    """.data(using: .utf8)
            }
            else if path.contains("version.plist") {
                return """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                    <plist version="1.0">
                    <dict>
                        <key>ProductBuildVersion</key>
                        <string>12D4e</string>
                    </dict>
                    </plist>
                    """.data(using: .utf8)
            }
            else {
                return nil
            }
        }
        
        subject.updateAllXcodes(
            availableXcodes: [
                AvailableXcode(version: Version("12.4.0+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
                AvailableXcode(version: Version("12.4.0-RC+12D4e")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil),
            ], 
            installedXcodes: [
                InstalledXcode(path: Path("/Applications/Xcode-12.4.0-RC.app")!)!
            ], 
            selectedXcodePath: nil
        )
        
        XCTAssertEqual(subject.allXcodes.map(\.version), [Version("12.4.0+12D4e")!])
        XCTAssertEqual(subject.allXcodes.map(\.identicalBuilds), [[Version("12.4.0+12D4e")!, Version("12.4.0-RC+12D4e")!]])
    }
}
