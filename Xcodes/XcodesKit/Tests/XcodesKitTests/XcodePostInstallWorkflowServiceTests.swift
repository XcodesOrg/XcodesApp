@preconcurrency import Path
import Version
import XCTest
@testable import XcodesKit

final class XcodePostInstallWorkflowServiceTests: XCTestCase {
    func testPerformPostInstallStepsRunsSharedSequence() async throws {
        let xcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!, version: Version("0.0.0")!)
        let recorder = StepRecorder()

        let service = XcodePostInstallWorkflowService(
            preparationService: XcodePostInstallPreparationService(
                enableDeveloperTools: { await recorder.append("enableDeveloperTools") },
                addStaffToDevelopersGroup: { await recorder.append("addStaffToDevelopersGroup") },
                acceptLicense: { receivedXcode in
                    await recorder.append("acceptLicense", receivedPath: receivedXcode.path)
                }
            ),
            postInstallService: XcodePostInstallService(
                runFirstLaunch: { receivedXcode in
                    await recorder.append("runFirstLaunch", receivedPath: receivedXcode.path)
                },
                getUserCacheDirectory: {
                    await recorder.append("getUserCacheDirectory")
                    return ProcessOutput(status: 0, out: "cache", err: "")
                },
                getMacOSBuildVersion: {
                    await recorder.append("getMacOSBuildVersion")
                    return ProcessOutput(status: 0, out: "macOS", err: "")
                },
                getXcodeBuildVersion: { receivedXcode in
                    await recorder.append("getXcodeBuildVersion", receivedPath: receivedXcode.path)
                    return ProcessOutput(status: 0, out: "tools", err: "")
                },
                touchInstallCheck: { cacheDirectory, macOSBuildVersion, toolsVersion in
                    XCTAssertEqual(cacheDirectory, "cache")
                    XCTAssertEqual(macOSBuildVersion, "macOS")
                    XCTAssertEqual(toolsVersion, "tools")
                    await recorder.append("touchInstallCheck")
                    return ProcessOutput(status: 0, out: "", err: "")
                }
            )
        )

        try await service.performPostInstallSteps(for: xcode)

        let steps = await recorder.steps
        XCTAssertEqual(Array(steps.prefix(3)), [
            "enableDeveloperTools",
            "addStaffToDevelopersGroup",
            "acceptLicense",
        ])
        XCTAssertEqual(steps.last, "touchInstallCheck")
        XCTAssertTrue(steps.contains("runFirstLaunch"))
        XCTAssertTrue(steps.contains("getUserCacheDirectory"))
        XCTAssertTrue(steps.contains("getMacOSBuildVersion"))
        XCTAssertTrue(steps.contains("getXcodeBuildVersion"))
        let receivedPaths = await recorder.receivedPaths
        XCTAssertEqual(receivedPaths, [xcode.path, xcode.path, xcode.path])
    }

    func testPostInstallServiceStopsAfterFirstLaunchWhenCancelled() async throws {
        let xcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!, version: Version("0.0.0")!)
        let recorder = StepRecorder()
        let firstLaunchContinuation = OneShotContinuation<Void>()
        let service = XcodePostInstallService(
            runFirstLaunch: { _ in
                await recorder.append("runFirstLaunch")
                try await withCheckedThrowingContinuation { continuation in
                    firstLaunchContinuation.setContinuation(continuation)
                }
            },
            getUserCacheDirectory: {
                await recorder.append("getUserCacheDirectory")
                return ProcessOutput(status: 0, out: "cache", err: "")
            },
            getMacOSBuildVersion: {
                await recorder.append("getMacOSBuildVersion")
                return ProcessOutput(status: 0, out: "macOS", err: "")
            },
            getXcodeBuildVersion: { _ in
                await recorder.append("getXcodeBuildVersion")
                return ProcessOutput(status: 0, out: "tools", err: "")
            },
            touchInstallCheck: { _, _, _ in
                await recorder.append("touchInstallCheck")
                return ProcessOutput(status: 0, out: "", err: "")
            }
        )

        let task = Task {
            try await service.installComponents(for: xcode)
        }
        for _ in 0..<100 where await recorder.steps.isEmpty {
            await Task.yield()
        }
        task.cancel()
        firstLaunchContinuation.resume()

        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let steps = await recorder.steps
        XCTAssertEqual(steps, ["runFirstLaunch"])
    }
}

private actor StepRecorder {
    private(set) var steps = [String]()
    private(set) var receivedPaths = [Path]()

    func append(_ step: String, receivedPath: Path? = nil) {
        steps.append(step)
        if let receivedPath {
            receivedPaths.append(receivedPath)
        }
    }
}
