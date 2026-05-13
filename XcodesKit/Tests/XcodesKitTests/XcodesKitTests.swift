// swiftlint:disable:next blanket_disable_command
// swiftlint:disable function_body_length
@testable import XcodesKit
import XCTest

final class XcodesKitTests: XCTestCase {
    func testDownloadableRuntimesDecodesPropertyListFromDataLoader() async throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>sdkToSimulatorMappings</key>
            <array>
                <dict>
                    <key>downloadableIdentifiers</key>
                    <array>
                        <string>com.apple.dmg.iPhoneSimulatorSDK18_0</string>
                    </array>
                    <key>sdkBuildUpdate</key>
                    <string>22A3351</string>
                    <key>sdkIdentifier</key>
                    <string>com.apple.platform.iphoneos</string>
                    <key>simulatorBuildUpdate</key>
                    <string>22A3351</string>
                </dict>
            </array>
            <key>sdkToSeedMappings</key>
            <array/>
            <key>refreshInterval</key>
            <integer>3600</integer>
            <key>downloadables</key>
            <array>
                <dict>
                    <key>category</key>
                    <string>simulator</string>
                    <key>simulatorVersion</key>
                    <dict>
                        <key>buildUpdate</key>
                        <string>22A3351</string>
                        <key>version</key>
                        <string>18.0</string>
                    </dict>
                    <key>source</key>
                    <string>https://example.com/iPhoneSimulatorSDK18_0.dmg</string>
                    <key>architectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>dictionaryVersion</key>
                    <integer>2</integer>
                    <key>contentType</key>
                    <string>diskImage</string>
                    <key>platform</key>
                    <string>com.apple.platform.iphoneos</string>
                    <key>identifier</key>
                    <string>com.apple.dmg.iPhoneSimulatorSDK18_0</string>
                    <key>version</key>
                    <string>18.0</string>
                    <key>fileSize</key>
                    <integer>1234</integer>
                    <key>name</key>
                    <string>iOS 18.0 Simulator Runtime</string>
                </dict>
            </array>
            <key>version</key>
            <string>2</string>
        </dict>
        </plist>
        """
        let data = try XCTUnwrap(plist.data(using: .utf8))
        let expectedURL = URL.downloadableRuntimes
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let service = RuntimeService { request in
            XCTAssertEqual(request.url, expectedURL)
            return (data, response)
        }

        let result = try await service.downloadableRuntimes()

        XCTAssertEqual(result.version, "2")
        XCTAssertEqual(result.downloadables.count, 1)
        XCTAssertEqual(result.downloadables.first?.identifier, "com.apple.dmg.iPhoneSimulatorSDK18_0")
        XCTAssertEqual(result.downloadables.first?.architectures, [.arm64])
    }
}
