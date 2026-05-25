import XCTest
@preconcurrency import Version
@testable import XcodesKit

final class ArchitectureFilteringTests: XCTestCase {
    func testAvailableXcodesCanBeFilteredByArchitecture() throws {
        let universal = availableXcode("15.0.0", filename: "Xcode-15.xip", architectures: [.arm64, .x86_64])
        let appleSilicon = availableXcode("16.0.0", filename: "Xcode-16-arm64.xip", architectures: [.arm64])
        let intel = availableXcode("14.0.0", filename: "Xcode-14-x86_64.xip", architectures: [.x86_64])
        let unknown = availableXcode("13.0.0", filename: "Xcode-13.xip")

        XCTAssertEqual(
            [universal, appleSilicon, intel, unknown].matchingArchitectures([.arm64]),
            [universal, appleSilicon]
        )
        XCTAssertEqual(
            [universal, appleSilicon, intel, unknown].matchingArchitectures([.x86_64]),
            [universal, intel]
        )
        XCTAssertEqual(
            [universal, appleSilicon, intel, unknown].matchingArchitectures([]),
            [universal, appleSilicon, intel, unknown]
        )
    }

    func testAvailableXcodesFirstCompatiblePrefersUniversalThenHostArchitecture() throws {
        let universal = availableXcode("26.2.0", filename: "Xcode-26-universal.xip", architectures: [.arm64, .x86_64])
        let appleSilicon = availableXcode("26.2.0", filename: "Xcode-26-arm64.xip", architectures: [.arm64])
        let intel = availableXcode("26.2.0", filename: "Xcode-26-x86_64.xip", architectures: [.x86_64])

        XCTAssertEqual([appleSilicon, universal, intel].firstCompatible(withVersion: Version("26.2.0")!, hostArchitecture: .arm64), universal)
        XCTAssertEqual([appleSilicon, intel].firstCompatible(withVersion: Version("26.2.0")!, hostArchitecture: .x86_64), intel)
    }

    func testXcodeListPresentationServiceFiltersAvailableRowsByArchitecture() throws {
        let universal = availableXcode("15.0.0", filename: "Xcode-15.xip", architectures: [.arm64, .x86_64])
        let appleSilicon = availableXcode("16.0.0", filename: "Xcode-16-arm64.xip", architectures: [.arm64])
        let intel = availableXcode("14.0.0", filename: "Xcode-14-x86_64.xip", architectures: [.x86_64])

        let rows = XcodeListPresentationService().availableRows(
            availableXcodes: [universal, appleSilicon, intel],
            installedXcodes: [],
            selectedXcodePath: nil,
            dataSource: .xcodeReleases,
            architectures: [.architecture(.arm64), .variant(.universal)]
        )

        XCTAssertEqual(rows.map(\.version), [universal.version, appleSilicon.version])
        XCTAssertEqual(rows.map(\.versionDescription), [
            "15.0 [Universal]",
            "16.0 [Apple Silicon]"
        ])
    }

    func testArchitectureFiltersParseRawArchitecturesAndVariants() {
        XCTAssertEqual(ArchitectureFilter("arm64"), .architecture(.arm64))
        XCTAssertEqual(ArchitectureFilter("x86_64"), .architecture(.x86_64))
        XCTAssertEqual(ArchitectureFilter("appleSilicon"), .variant(.appleSilicon))
        XCTAssertEqual(ArchitectureFilter("universal"), .variant(.universal))
    }

    func testArchitectureFiltersKeepUnknownArchitectureEntriesVisible() {
        XCTAssertTrue([ArchitectureFilter.variant(.appleSilicon)].matches(nil))
        XCTAssertTrue([ArchitectureFilter.variant(.universal)].matches([]))
    }

    func testDefaultArchitectureFilterUsesMachineArchitecture() {
        XCTAssertEqual(ArchitectureVariant.defaultForMachine(machineHardwareName: "arm64"), .appleSilicon)
        XCTAssertEqual(ArchitectureVariant.defaultForMachine(machineHardwareName: "x86_64"), .universal)
        XCTAssertEqual([ArchitectureFilter].defaultForMachine(machineHardwareName: "arm64"), [.variant(.appleSilicon)])
        XCTAssertEqual([ArchitectureFilter].defaultForMachine(machineHardwareName: "x86_64"), [.variant(.universal)])
    }

    func testRuntimeListPresentationServiceFiltersRowsByArchitecture() {
        let response = DownloadableRuntimesResponse(
            sdkToSimulatorMappings: [],
            sdkToSeedMappings: [],
            refreshInterval: 3600,
            downloadables: [
                downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg", architectures: [.arm64, .x86_64]),
                downloadableRuntime(
                    source: "https://example.com/iOS_17_Runtime.dmg",
                    architectures: [.arm64],
                    simulatorVersion: .init(buildUpdate: "21A1", version: "17.0"),
                    identifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                    name: "iOS 17.0"
                ),
                downloadableRuntime(
                    source: "https://example.com/iOS_15_Runtime.dmg",
                    architectures: [.x86_64],
                    simulatorVersion: .init(buildUpdate: "19A1", version: "15.0"),
                    identifier: "com.apple.CoreSimulator.SimRuntime.iOS-15-0",
                    name: "iOS 15.0"
                )
            ],
            version: "2"
        )

        let rows = RuntimeListPresentationService().rows(
            downloadableRuntimes: response,
            installedRuntimes: [],
            includeBetas: false,
            architectures: [.architecture(.arm64), .variant(.universal)]
        )

        XCTAssertEqual(rows.first?.runtimes.map(\.visibleIdentifier), [
            "iOS 16.0 [Universal]",
            "iOS 17.0 [Apple Silicon]"
        ])
    }

    private func availableXcode(_ version: String, filename: String, architectures: [Architecture]? = nil) -> AvailableXcode {
        AvailableXcode(
            version: Version(version)!,
            url: URL(fileURLWithPath: "/" + filename),
            filename: filename,
            releaseDate: nil,
            architectures: architectures
        )
    }

    private func downloadableRuntime(
        source: String?,
        architectures: [Architecture]? = nil,
        simulatorVersion: DownloadableRuntime.SimulatorVersion = .init(buildUpdate: "20A360", version: "16.0"),
        identifier: String = "com.apple.CoreSimulator.SimRuntime.iOS-16-0",
        name: String = "iOS 16.0"
    ) -> DownloadableRuntime {
        DownloadableRuntime(
            category: .simulator,
            simulatorVersion: simulatorVersion,
            source: source,
            architectures: architectures,
            dictionaryVersion: 1,
            contentType: .diskImage,
            platform: .iOS,
            identifier: identifier,
            version: simulatorVersion.version,
            fileSize: 42,
            hostRequirements: nil,
            name: name,
            authentication: nil
        )
    }
}
