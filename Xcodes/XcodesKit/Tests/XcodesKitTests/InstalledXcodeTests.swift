import XCTest
@preconcurrency import Path
import Version
import os
@testable import XcodesKit

final class InstalledXcodeTests: XCTestCase {
    func testInitParsesBundleInfoAndArchitecturesFromInjectedLoaders() throws {
        let path = try XCTUnwrap(Path("/Applications/Xcode-15.0.0.app"))
        let architectureURL = URLRecorder()

        let xcode = try XCTUnwrap(InstalledXcode(
            path: path,
            contentsAtPath: { requestedPath in
                switch requestedPath {
                case "/Applications/Xcode-15.0.0.app/Contents/Info.plist":
                    return Self.plistData("""
                    <dict>
                        <key>CFBundleIdentifier</key>
                        <string>com.apple.dt.Xcode</string>
                        <key>CFBundleShortVersionString</key>
                        <string>15.0</string>
                    </dict>
                    """)
                case "/Applications/Xcode-15.0.0.app/Contents/version.plist":
                    return Self.plistData("""
                    <dict>
                        <key>ProductBuildVersion</key>
                        <string>15A240d</string>
                    </dict>
                    """)
                default:
                    XCTFail("Unexpected path \(requestedPath)")
                    return nil
                }
            },
            loadArchitectures: { url in
                architectureURL.record(url)
                return (0, "x86_64 arm64\n", "")
            }
        ))

        XCTAssertEqual(xcode.path, path)
        XCTAssertEqual(xcode.version, Version("15.0.0+15A240d"))
        XCTAssertEqual(xcode.xcodeID.architectures, [.x86_64, .arm64])
        XCTAssertEqual(architectureURL.url?.path, "/Applications/Xcode-15.0.0.app/Contents/MacOS/Xcode")
    }

    func testInitReturnsNilForNonXcodeBundle() throws {
        let path = try XCTUnwrap(Path("/Applications/Other.app"))

        let xcode = InstalledXcode(
            path: path,
            contentsAtPath: { requestedPath in
                switch requestedPath {
                case "/Applications/Other.app/Contents/Info.plist":
                    return Self.plistData("""
                    <dict>
                        <key>CFBundleIdentifier</key>
                        <string>com.example.Other</string>
                        <key>CFBundleShortVersionString</key>
                        <string>15.0</string>
                    </dict>
                    """)
                case "/Applications/Other.app/Contents/version.plist":
                    return Self.plistData("""
                    <dict>
                        <key>ProductBuildVersion</key>
                        <string>15A240d</string>
                    </dict>
                    """)
                default:
                    return nil
                }
            },
            loadArchitectures: { _ in (0, "arm64\n", "") }
        )

        XCTAssertNil(xcode)
    }

    func testInitReturnsNilWhenBundleInfoCannotBeLoaded() throws {
        let path = try XCTUnwrap(Path("/Applications/Xcode.app"))

        let xcode = InstalledXcode(
            path: path,
            contentsAtPath: { _ in nil },
            loadArchitectures: { _ in
                XCTFail("Architectures should not be loaded without bundle info")
                return (0, "", "")
            }
        )

        XCTAssertNil(xcode)
    }

    func testDiscoveryServiceLoadsInstalledXcodesFromInjectedDirectoryListing() throws {
        let xcodePath = try XCTUnwrap(Path("/Applications/Xcode.app"))
        let otherPath = try XCTUnwrap(Path("/Applications/Other.app"))
        let ignoredPath = try XCTUnwrap(Path("/Applications/README.txt"))

        let service = InstalledXcodeDiscoveryService(
            listDirectory: { directory in
                XCTAssertEqual(directory, try! XCTUnwrap(Path("/Applications")))
                return [xcodePath, otherPath, ignoredPath]
            },
            isAppBundle: { $0.extension == "app" },
            contentsAtPath: { requestedPath in
                switch requestedPath {
                case "/Applications/Xcode.app/Contents/Info.plist":
                    return Self.plistData("""
                    <dict>
                        <key>CFBundleIdentifier</key>
                        <string>com.apple.dt.Xcode</string>
                        <key>CFBundleShortVersionString</key>
                        <string>15.0</string>
                    </dict>
                    """)
                case "/Applications/Xcode.app/Contents/version.plist":
                    return Self.plistData("""
                    <dict>
                        <key>ProductBuildVersion</key>
                        <string>15A240d</string>
                    </dict>
                    """)
                case "/Applications/Other.app/Contents/Info.plist":
                    return Self.plistData("""
                    <dict>
                        <key>CFBundleIdentifier</key>
                        <string>com.example.Other</string>
                        <key>CFBundleShortVersionString</key>
                        <string>1.0</string>
                    </dict>
                    """)
                case "/Applications/Other.app/Contents/version.plist":
                    return Self.plistData("""
                    <dict>
                        <key>ProductBuildVersion</key>
                        <string>1A1</string>
                    </dict>
                    """)
                default:
                    return nil
                }
            },
            loadArchitectures: { _ in (0, "arm64\n", "") }
        )

        let xcodes = service.installedXcodes(in: try XCTUnwrap(Path("/Applications")))

        XCTAssertEqual(xcodes, [
            InstalledXcode(path: xcodePath, version: Version("15.0.0+15A240d")!, architectures: [.arm64])
        ])
    }

    private static func plistData(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        \(body)
        </plist>
        """.utf8)
    }
}

private final class URLRecorder: Sendable {
    private let storedURL = OSAllocatedUnfairLock<URL?>(initialState: nil)

    var url: URL? {
        storedURL.withLock { $0 }
    }

    func record(_ url: URL) {
        storedURL.withLock { $0 = url }
    }
}
