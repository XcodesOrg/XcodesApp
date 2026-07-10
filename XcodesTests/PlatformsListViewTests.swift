import XCTest
import XcodesKit
import OrderedCollections

@testable import Xcodes

final class PlatformsListViewTests: XCTestCase {

    private func downloadableRuntime(
        name: String,
        identifier: String,
        platform: String = "com.apple.platform.iphoneos",
        version: String,
        buildUpdate: String,
        fileSize: Int,
        architectures: [String]?
    ) throws -> DownloadableRuntime {
        let architecturesJSON: String
        if let architectures {
            architecturesJSON = "[" + architectures.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        } else {
            architecturesJSON = "null"
        }
        let json = """
        {
          "category": "simulator",
          "simulatorVersion": {
            "buildUpdate": "\(buildUpdate)",
            "version": "\(version)"
          },
          "source": "https://example.com/\(identifier).dmg",
          "architectures": \(architecturesJSON),
          "dictionaryVersion": 1,
          "contentType": "diskImage",
          "platform": "\(platform)",
          "identifier": "\(identifier)",
          "version": "\(version)",
          "fileSize": \(fileSize),
          "hostRequirements": null,
          "name": "\(name)",
          "authentication": null
        }
        """
        return try JSONDecoder().decode(DownloadableRuntime.self, from: Data(json.utf8))
    }

    /// Apple ships a Universal and an arm64-only download for the same installed
    /// build (same name, same buildUpdate, different identifier/architectures).
    /// A single installed runtime must collapse to a single row.
    func test_InstalledRuntimeRows_CollapsesUniversalAndArm64VariantsOfSameInstall() throws {
        let universal = try downloadableRuntime(
            name: "iOS 26.4 Simulator Runtime",
            identifier: "com.apple.dmg.iPhoneSimulatorSDK26_4",
            version: "26.4",
            buildUpdate: "23E244",
            fileSize: 10_603_482_987,
            architectures: ["arm64", "x86_64"]
        )
        let arm64Only = try downloadableRuntime(
            name: "iOS 26.4 Simulator Runtime",
            identifier: "com.apple.dmg.iPhoneSimulatorSDK26_4_arm64",
            version: "26.4",
            buildUpdate: "23E244",
            fileSize: 8_455_792_717,
            architectures: ["arm64"]
        )

        let installed = CoreSimulatorImage(
            uuid: "D6068E04-6529-4EC4-8EF8-A6050AB3EB7F",
            path: ["relative": "file:///some/path/iOS_26_4.dmg"],
            runtimeInfo: CoreSimulatorRuntimeInfo(build: "23E244", supportedArchitectures: [.arm64])
        )

        let grouped = PlatformsListView.installedRuntimeRows(
            downloadableRuntimes: [universal, arm64Only],
            installedRuntimes: [installed]
        )

        let iosRows = grouped[.iOS] ?? []
        XCTAssertEqual(
            iosRows.count,
            1,
            "A single installed 26.4 must produce one row, not one per architecture variant"
        )
        // The installed image is arm64-only, so the arm64 download is the better match.
        XCTAssertEqual(iosRows.first?.identifier, "com.apple.dmg.iPhoneSimulatorSDK26_4_arm64")
    }

    /// Distinct installed builds must each get their own row.
    func test_InstalledRuntimeRows_KeepsDistinctInstalledBuilds() throws {
        let ios186 = try downloadableRuntime(
            name: "iOS 18.6 Simulator Runtime",
            identifier: "com.apple.dmg.iPhoneSimulatorSDK18_6",
            version: "18.6",
            buildUpdate: "22G86",
            fileSize: 9_000_000_000,
            architectures: nil
        )
        let ios264 = try downloadableRuntime(
            name: "iOS 26.4 Simulator Runtime",
            identifier: "com.apple.dmg.iPhoneSimulatorSDK26_4_arm64",
            version: "26.4",
            buildUpdate: "23E244",
            fileSize: 8_455_792_717,
            architectures: ["arm64"]
        )

        let installed186 = CoreSimulatorImage(
            uuid: "11111111-1111-1111-1111-111111111111",
            path: ["relative": "file:///some/path/iOS_18_6.dmg"],
            runtimeInfo: CoreSimulatorRuntimeInfo(build: "22G86")
        )
        let installed264 = CoreSimulatorImage(
            uuid: "22222222-2222-2222-2222-222222222222",
            path: ["relative": "file:///some/path/iOS_26_4.dmg"],
            runtimeInfo: CoreSimulatorRuntimeInfo(build: "23E244", supportedArchitectures: [.arm64])
        )

        let grouped = PlatformsListView.installedRuntimeRows(
            downloadableRuntimes: [ios186, ios264],
            installedRuntimes: [installed186, installed264]
        )

        XCTAssertEqual((grouped[.iOS] ?? []).count, 2, "Two distinct installed builds must produce two rows")
    }

    /// Downloadable runtimes that are not installed locally must not appear.
    func test_InstalledRuntimeRows_ExcludesNotInstalledRuntimes() throws {
        let notInstalled = try downloadableRuntime(
            name: "iOS 27.0 Simulator Runtime",
            identifier: "com.apple.dmg.iPhoneSimulatorSDK27_0",
            version: "27.0",
            buildUpdate: "25A000",
            fileSize: 9_000_000_000,
            architectures: ["arm64"]
        )

        let installed = CoreSimulatorImage(
            uuid: "33333333-3333-3333-3333-333333333333",
            path: ["relative": "file:///some/path/iOS_26_4.dmg"],
            runtimeInfo: CoreSimulatorRuntimeInfo(build: "23E244", supportedArchitectures: [.arm64])
        )

        let grouped = PlatformsListView.installedRuntimeRows(
            downloadableRuntimes: [notInstalled],
            installedRuntimes: [installed]
        )

        XCTAssertTrue(grouped.isEmpty, "Runtimes that aren't installed locally must not be listed")
    }
}
