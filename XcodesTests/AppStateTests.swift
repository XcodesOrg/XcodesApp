import Combine
@preconcurrency import Path
import Version
import XCTest
import XcodesLoginKit
import XcodesKit
import os

@testable import Xcodes

private final class TestLockedBox<Value: Sendable>: Sendable {
    private let storage: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        self.storage = OSAllocatedUnfairLock(initialState: value)
    }

    func read<Result: Sendable>(_ body: @Sendable (Value) -> Result) -> Result {
        storage.withLock { body($0) }
    }

    func withValue<Result: Sendable>(_ body: @Sendable (inout Value) -> Result) -> Result {
        storage.withLock { body(&$0) }
    }
}

@MainActor
class AppStateTests: XCTestCase {
    var subject: AppState!
    
    override func setUpWithError() throws {
        Current = .mock
        syncXcodesKitMocks()
        subject = AppState()
    }
    
    func test_ParseCertificateInfo_Succeeds() throws {
        let sampleRawInfo = """
        Executable=/Applications/Xcode-10.1.app/Contents/MacOS/Xcode
        Identifier=com.apple.dt.Xcode
        Format=app bundle with Mach-O thin (x86_64)
        CodeDirectory v=20200 size=434 flags=0x2000(library-validation) hashes=6+5 location=embedded
        Signature size=4485
        Authority=Software Signing
        Authority=Apple Code Signing Certification Authority
        Authority=Apple Root CA
        Info.plist entries=39
        TeamIdentifier=59GAB85EFG
        Sealed Resources version=2 rules=13 files=253327
        Internal requirements count=1 size=68
        """
        let info = XcodeSignatureVerifier().parse(sampleRawInfo)

        XCTAssertEqual(info.authority, ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"])
        XCTAssertEqual(info.teamIdentifier, "59GAB85EFG")
        XCTAssertEqual(info.bundleIdentifier, "com.apple.dt.Xcode")
    }

    func test_PrepareForHelperAction_OnlyRunsActionOnce() {
        var responses = [Bool]()
        subject.prepareForHelperAction { responses.append($0) }

        let helperAction = subject.isPreparingUserForActionRequiringHelper
        helperAction?(true)
        helperAction?(false)

        XCTAssertEqual(responses, [true])
        XCTAssertNil(subject.isPreparingUserForActionRequiringHelper)
    }

    func test_SetupDefaults_EnableGroupedXcodeListDefaultsToTrue() {
        subject.setupDefaults()

        XCTAssertTrue(subject.enableGroupedXcodeList)
    }

    func test_SetupDefaults_EnableGroupedXcodeListUsesStoredValue() {
        Current.defaults.get = { key in
            key == PreferenceKey.enableGroupedXcodeList.rawValue ? false : nil
        }

        subject.setupDefaults()

        XCTAssertFalse(subject.enableGroupedXcodeList)
    }

    func test_PrepareForHelperAction_StaleActionDoesNotClearReplacementAction() {
        var responses = [Bool]()
        subject.prepareForHelperAction { responses.append($0) }
        let staleHelperAction = subject.isPreparingUserForActionRequiringHelper

        subject.prepareForHelperAction { responses.append($0) }
        let replacementHelperAction = subject.isPreparingUserForActionRequiringHelper

        staleHelperAction?(true)
        XCTAssertTrue(responses.isEmpty)
        XCTAssertNotNil(subject.isPreparingUserForActionRequiringHelper)

        replacementHelperAction?(false)
        XCTAssertEqual(responses, [false])
        XCTAssertNil(subject.isPreparingUserForActionRequiringHelper)
        XCTAssertNil(subject.helperActionPreparationID)
    }

    func test_RespondToPreparedHelperAction_RunsActionAndClearsAlert() {
        var responses = [Bool]()
        subject.prepareForHelperAction { responses.append($0) }

        subject.respondToPreparedHelperAction(userConsented: true)

        XCTAssertEqual(responses, [true])
        XCTAssertNil(subject.isPreparingUserForActionRequiringHelper)
        XCTAssertNil(subject.helperActionPreparationID)
        XCTAssertNil(subject.presentedAlert)
    }

    func test_CreateSymbolicLink_UsesProvidedInstalledPath() throws {
        let installDirectory = try XCTUnwrap(Path(
            NSTemporaryDirectory()
                .appending("XcodesAppStateTests-")
                .appending(UUID().uuidString)
        ))
        let installedXcodePath = installDirectory/"Xcode-15.1.app"
        let symlinkPath = installDirectory/"Xcode.app"
        try FileManager.default.createDirectory(at: installedXcodePath.url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: installDirectory.url) }

        Current.defaults.string = { key in
            key == "installPath" ? installDirectory.string : nil
        }

        subject.createSymbolicLink(to: installedXcodePath)

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath.string)
        XCTAssertEqual(destination, installedXcodePath.string)
    }

    func test_InstallHelperIfNecessary_OldTaskDoesNotClearReplacementTask() async throws {
        subject.helperInstallState = .notInstalled
        let continuations = TestLockedBox<[CheckedContinuation<Bool, Error>]>([])
        Current.helper.install = { }
        Current.helper.checkIfLatestHelperIsInstalledAsync = {
            try await withCheckedThrowingContinuation { continuation in
                continuations.withValue { $0.append(continuation) }
            }
        }

        subject.installHelperIfNecessary(shouldPrepareUserForHelperInstallation: false)
        for _ in 0..<100 where continuations.read({ $0.count }) < 1 {
            await Task.yield()
        }
        let firstTask = try XCTUnwrap(subject.helperInstallTask)
        XCTAssertEqual(continuations.read { $0.count }, 1)

        subject.installHelperIfNecessary(shouldPrepareUserForHelperInstallation: false)
        for _ in 0..<100 where continuations.read({ $0.count }) < 2 {
            await Task.yield()
        }
        let replacementTask = try XCTUnwrap(subject.helperInstallTask)
        XCTAssertEqual(continuations.read { $0.count }, 2)

        continuations.read { $0[0] }.resume(returning: false)
        await firstTask.value
        XCTAssertNotNil(subject.helperInstallTask)

        continuations.read { $0[1] }.resume(returning: true)
        await replacementTask.value
        XCTAssertNil(subject.helperInstallTask)
        XCTAssertNil(subject.helperInstallTaskID)
        XCTAssertEqual(subject.helperInstallState, .installed)
    }

    func test_PerformPostInstallSteps_OldTaskDoesNotClearReplacementTask() async throws {
        subject.helperInstallState = .installed
        let firstXcode = InstalledXcode(path: Path("/Applications/Xcode-1.app")!, version: Version("1.0.0")!)
        let secondXcode = InstalledXcode(path: Path("/Applications/Xcode-2.app")!, version: Version("2.0.0")!)
        let firstLaunchPaths = TestLockedBox<[String]>([])
        let continuations = TestLockedBox<[CheckedContinuation<Void, Error>]>([])

        Current.helper.runFirstLaunchAsync = { path in
            firstLaunchPaths.withValue { $0.append(path) }
            try await withCheckedThrowingContinuation { continuation in
                continuations.withValue { $0.append(continuation) }
            }
        }

        subject.performPostInstallSteps(for: firstXcode)
        for _ in 0..<100 where continuations.read({ $0.count }) < 1 {
            await Task.yield()
        }
        let firstTask = try XCTUnwrap(subject.postInstallTask)
        XCTAssertEqual(firstLaunchPaths.read { $0 }, [firstXcode.path.string])

        subject.performPostInstallSteps(for: secondXcode)
        for _ in 0..<100 where continuations.read({ $0.count }) < 2 {
            await Task.yield()
        }
        let replacementTask = try XCTUnwrap(subject.postInstallTask)
        XCTAssertEqual(firstLaunchPaths.read { $0 }, [firstXcode.path.string, secondXcode.path.string])

        continuations.read { $0[0] }.resume()
        await firstTask.value
        XCTAssertNotNil(subject.postInstallTask)

        continuations.read { $0[1] }.resume()
        await replacementTask.value
        XCTAssertNil(subject.postInstallTask)
        XCTAssertNil(subject.postInstallTaskID)
    }

    func test_Select_OldTaskDoesNotClearReplacementTask() async throws {
        subject.helperInstallState = .installed
        let firstPath = try XCTUnwrap(Path("/Applications/Xcode-1.app"))
        let secondPath = try XCTUnwrap(Path("/Applications/Xcode-2.app"))
        let firstXcode = Xcode(version: Version("1.0.0")!, installState: .installed(firstPath), selected: false, icon: nil)
        let secondXcode = Xcode(version: Version("2.0.0")!, installState: .installed(secondPath), selected: false, icon: nil)
        let selectedPaths = TestLockedBox<[String]>([])
        let continuations = TestLockedBox<[CheckedContinuation<Void, Error>]>([])

        Current.helper.switchXcodePathAsync = { path in
            selectedPaths.withValue { $0.append(path) }
            try await withCheckedThrowingContinuation { continuation in
                continuations.withValue { $0.append(continuation) }
            }
        }
        Current.shell.xcodeSelectPrintPath = {
            ProcessOutput(status: 0, out: secondPath.string, err: "")
        }

        subject.select(xcode: firstXcode, shouldPrepareUserForHelperInstallation: false)
        for _ in 0..<100 where continuations.read({ $0.count }) < 1 {
            await Task.yield()
        }
        let firstTask = try XCTUnwrap(subject.selectTask)
        XCTAssertEqual(selectedPaths.read { $0 }, [firstPath.string])

        subject.select(xcode: secondXcode, shouldPrepareUserForHelperInstallation: false)
        for _ in 0..<100 where continuations.read({ $0.count }) < 2 {
            await Task.yield()
        }
        let replacementTask = try XCTUnwrap(subject.selectTask)
        XCTAssertEqual(selectedPaths.read { $0 }, [firstPath.string, secondPath.string])

        continuations.read { $0[0] }.resume()
        await firstTask.value
        XCTAssertNotNil(subject.selectTask)

        continuations.read { $0[1] }.resume()
        await replacementTask.value
        XCTAssertNil(subject.selectTask)
        XCTAssertNil(subject.selectTaskID)
        XCTAssertEqual(subject.selectedXcodePath, secondPath.string)
    }

    func test_Signout_RemovesCookiesFromDownloadSession() throws {
        let session = URLSession(configuration: .ephemeral)
        Current.network.session = session
        let cookie = try HTTPCookie.xcodesTestCookie(name: "ADCDownloadAuth")
        session.configuration.httpCookieStorage?.setCookie(cookie)
        XCTAssertEqual(session.configuration.httpCookieStorage?.cookies?.contains(cookie), true)

        subject.signOut()

        XCTAssertEqual(session.configuration.httpCookieStorage?.cookies?.contains(cookie), false)
    }

    func test_Signout_RemovesCookiesAfterDownloadSessionIsReplaced() throws {
        let initialSession = URLSession(configuration: .ephemeral)
        let replacementSession = URLSession(configuration: .ephemeral)
        Current.network.session = initialSession
        Current.network.session = replacementSession
        let cookie = try HTTPCookie.xcodesTestCookie(name: "FASTLANE_SESSION")
        replacementSession.configuration.httpCookieStorage?.setCookie(cookie)
        XCTAssertEqual(replacementSession.configuration.httpCookieStorage?.cookies?.contains(cookie), true)

        subject.signOut()

        XCTAssertEqual(initialSession.configuration.httpCookieStorage?.cookies?.contains(cookie), false)
        XCTAssertEqual(replacementSession.configuration.httpCookieStorage?.cookies?.contains(cookie), false)
    }

    func test_NetworkSessionReplacementUpdatesLoginClientSession() {
        let initialSession = URLSession(configuration: .ephemeral)
        let replacementSession = URLSession(configuration: .ephemeral)

        Current.network.session = initialSession
        XCTAssertTrue(Current.network.loginClient.urlSession === initialSession)

        Current.network.session = replacementSession
        XCTAssertTrue(Current.network.loginClient.urlSession === replacementSession)
    }

    func test_DownloadRuntimeViaXcodeBuild_ClearsRuntimeTaskWhenComplete() async throws {
        let runtime = try Self.downloadableRuntime()
        subject.downloadableRuntimes = [runtime]
        Current.shell.downloadRuntime = { _, _, _ in
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Progress.self, throwing: Error.self)
            continuation.finish()
            return stream
        }

        subject.downloadRuntimeViaXcodeBuild(runtime: runtime)
        let task = try XCTUnwrap(subject.runtimeTasks[runtime.identifier])
        try await task.value

        XCTAssertNil(subject.runtimeTasks[runtime.identifier])
        XCTAssertNil(subject.runtimeTaskIDs[runtime.identifier])
        XCTAssertEqual(subject.downloadableRuntimes.first?.installState, .installed)
    }

    func test_DownloadRuntimeViaXcodeBuild_OldTaskDoesNotClearReplacementTask() async throws {
        let runtime = try Self.downloadableRuntime()
        subject.downloadableRuntimes = [runtime]
        let continuations = TestLockedBox<[AsyncThrowingStream<Progress, Error>.Continuation]>([])
        Current.shell.downloadRuntime = { _, _, _ in
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Progress.self, throwing: Error.self)
            continuations.withValue { $0.append(continuation) }
            return stream
        }

        subject.downloadRuntimeViaXcodeBuild(runtime: runtime)
        for _ in 0..<100 where continuations.read({ $0.count }) < 1 {
            await Task.yield()
        }
        let firstTask = try XCTUnwrap(subject.runtimeTasks[runtime.identifier])
        XCTAssertEqual(continuations.read { $0.count }, 1)

        subject.downloadRuntimeViaXcodeBuild(runtime: runtime)
        for _ in 0..<100 where continuations.read({ $0.count }) < 2 {
            await Task.yield()
        }
        let replacementTask = try XCTUnwrap(subject.runtimeTasks[runtime.identifier])
        XCTAssertEqual(continuations.read { $0.count }, 2)

        continuations.read { $0[0] }.finish()
        try await firstTask.value
        XCTAssertNotNil(subject.runtimeTasks[runtime.identifier])

        continuations.read { $0[1] }.finish()
        try await replacementTask.value
        XCTAssertNil(subject.runtimeTasks[runtime.identifier])
        XCTAssertNil(subject.runtimeTaskIDs[runtime.identifier])
    }

    func test_ConfirmDeleteRuntime_OldTaskDoesNotClearReplacementTask() async throws {
        let runtime = try Self.downloadableRuntime()
        let installedRuntime = CoreSimulatorImage(
            uuid: "runtime-uuid",
            path: ["relative": "/Library/Developer/CoreSimulator/Images/runtime.dmg"],
            runtimeInfo: CoreSimulatorRuntimeInfo(build: runtime.simulatorVersion.buildUpdate)
        )
        let deletedIdentifiers = TestLockedBox<[String]>([])
        let continuations = TestLockedBox<[CheckedContinuation<ProcessOutput, Error>]>([])
        subject = AppState(
            runtimeService: Self.runtimeService { identifier in
                deletedIdentifiers.withValue { $0.append(identifier) }
                return try await withCheckedThrowingContinuation { continuation in
                    continuations.withValue { $0.append(continuation) }
                }
            }
        )
        subject.installedRuntimes = [installedRuntime]

        subject.confirmDeleteRuntime(runtime: runtime)
        for _ in 0..<100 where continuations.read({ $0.count }) < 1 {
            await Task.yield()
        }
        let firstTask = try XCTUnwrap(subject.deleteRuntimeTask)
        XCTAssertEqual(deletedIdentifiers.read { $0 }, [installedRuntime.uuid])

        subject.confirmDeleteRuntime(runtime: runtime)
        for _ in 0..<100 where continuations.read({ $0.count }) < 2 {
            await Task.yield()
        }
        let replacementTask = try XCTUnwrap(subject.deleteRuntimeTask)
        XCTAssertEqual(deletedIdentifiers.read { $0 }, [installedRuntime.uuid, installedRuntime.uuid])

        continuations.read { $0[0] }.resume(returning: ProcessOutput(status: 0, out: "", err: ""))
        await firstTask.value
        XCTAssertNotNil(subject.deleteRuntimeTask)

        continuations.read { $0[1] }.resume(returning: ProcessOutput(status: 0, out: "", err: ""))
        await replacementTask.value
        XCTAssertNil(subject.deleteRuntimeTask)
        XCTAssertNil(subject.deleteRuntimeTaskID)
    }

    func test_ConfirmDeleteRuntime_PresentsPreferenceAlertOnError() async throws {
        let runtime = try Self.downloadableRuntime()

        subject.confirmDeleteRuntime(runtime: runtime)
        let task = try XCTUnwrap(subject.deleteRuntimeTask)
        await task.value

        guard case let .generic(title, message) = subject.presentedPreferenceAlert else {
            return XCTFail("Expected generic preference alert")
        }
        XCTAssertEqual(title, "Error")
        XCTAssertEqual(message, "No simulator found with \(runtime.identifier)")
        XCTAssertNil(subject.deleteRuntimeTask)
        XCTAssertNil(subject.deleteRuntimeTaskID)
    }

    func test_InstallWithoutLogin_OldTaskDoesNotClearReplacementTask() async throws {
        let version = Version("0.0.0")!
        let availableXcode = AvailableXcode(
            version: version,
            url: URL(string: "https://apple.com/xcode.xip")!,
            filename: "mock.xip",
            releaseDate: nil
        )
        subject.availableXcodes = [availableXcode]
        subject.allXcodes = [
            .init(version: version, installState: .notInstalled, selected: false, icon: nil)
        ]
        subject.helperInstallState = .installed

        Current.defaults.string = { key in
            key == "downloader" ? "urlSession" : nil
        }
        Current.files.fileExistsAtPath = { path in
            path != (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string
        }
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeTeamIdentifier)
                    Authority=\(XcodeCertificateAuthority[0])
                    Authority=\(XcodeCertificateAuthority[1])
                    Authority=\(XcodeCertificateAuthority[2])
                    """
            )
        }

        let continuations = TestLockedBox<[CheckedContinuation<(saveLocation: URL, response: URLResponse), Error>]>([])
        Current.network.downloadTaskAsync = { url, saveLocation, _ in
            (
                Progress(),
                Task {
                    try await withCheckedThrowingContinuation { continuation in
                        continuations.withValue { $0.append(continuation) }
                    }
                }
            )
        }

        subject.installWithoutLogin(id: availableXcode.xcodeID)
        for _ in 0..<100 where continuations.read({ $0.count }) < 1 {
            await Task.yield()
        }
        let firstTask = try XCTUnwrap(subject.installationTasks[availableXcode.xcodeID])
        XCTAssertEqual(continuations.read { $0.count }, 1)

        subject.installWithoutLogin(id: availableXcode.xcodeID)
        for _ in 0..<100 where continuations.read({ $0.count }) < 2 {
            await Task.yield()
        }
        let replacementTask = try XCTUnwrap(subject.installationTasks[availableXcode.xcodeID])
        XCTAssertEqual(continuations.read { $0.count }, 2)

        continuations.read { $0[0] }.resume(returning: Self.downloadResult(for: availableXcode))
        await firstTask.value
        XCTAssertNotNil(subject.installationTasks[availableXcode.xcodeID])

        continuations.read { $0[1] }.resume(returning: Self.downloadResult(for: availableXcode))
        await replacementTask.value
        XCTAssertNil(subject.installationTasks[availableXcode.xcodeID])
        XCTAssertNil(subject.installationTaskIDs[availableXcode.xcodeID])
    }

    func test_Install_RetryingDownloadDoesNotAttachSameProgressTwice() async throws {
        let version = Version("0.0.0")!
        let availableXcode = AvailableXcode(
            version: version,
            url: URL(string: "https://apple.com/xcode.xip")!,
            filename: "mock.xip",
            releaseDate: nil
        )
        subject.allXcodes = [
            .init(version: version, installState: .notInstalled, selected: false, icon: nil)
        ]
        subject.helperInstallState = .installed

        Current.files.fileExistsAtPath = { path in
            path != (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string
        }
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeTeamIdentifier)
                    Authority=\(XcodeCertificateAuthority[0])
                    Authority=\(XcodeCertificateAuthority[1])
                    Authority=\(XcodeCertificateAuthority[2])
                    """
            )
        }

        let progress = Progress(totalUnitCount: 100)
        let attempts = TestLockedBox(0)
        Current.network.downloadTaskAsync = { url, saveLocation, _ in
            let attempt = attempts.withValue {
                $0 += 1
                return $0
            }
            return (
                progress,
                Task {
                    await Task.yield()
                    if attempt == 1 {
                        throw NSError(
                            domain: NSURLErrorDomain,
                            code: NSURLErrorNetworkConnectionLost,
                            userInfo: [NSURLSessionDownloadTaskResumeData: Data("resume".utf8)]
                        )
                    }

                    return (
                        saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    )
                }
            )
        }

        let installedXcode = try await subject.installAsync(
            .version(availableXcode),
            downloader: .urlSession,
            attemptNumber: 0
        )

        XCTAssertEqual(attempts.read { $0 }, 2)
        XCTAssertTrue(installedXcode.version.isEquivalent(to: version))
    }
    
    func test_Install_FullHappyPath_Apple() async throws {
        // Available xcode doesn't necessarily have build identifier
        subject.allXcodes = [
            .init(version: Version("0.0.0")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.1")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.2")!, installState: .notInstalled, selected: false, icon: nil),
        ]
        
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        Xcodes.Current.network.validateSessionAsync = { }
        Xcodes.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(resultCode: 0, resultsString: nil, downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip", fileSize: 9484444)], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (
                    data: downloadsData,
                    response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }

            return (
                data: Data(),
                response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        Current.network.downloadTaskAsync = { url, saveLocation, _ in
            return (
                progress,
                Task {
                    await Task.yield()
                    await MainActor.run {
                        for i in 0...100 {
                            progress.completedUnitCount = Int64(i)
                        }
                    }
                    return (
                        saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    )
                }
            )
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeTeamIdentifier)
                        Authority=\(XcodeCertificateAuthority[0])
                        Authority=\(XcodeCertificateAuthority[1])
                        Authority=\(XcodeCertificateAuthority[2])
                        """)
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        let allXcodeInstallStates = try await recordAllXcodeInstallStates {
            _ = try await subject.installAsync(
                .version(AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)),
                downloader: .urlSession,
                attemptNumber: 0
            )
        }

        XCTAssertEqual(
            allXcodeInstallStates,
            [
                [XcodeInstallState.notInstalled, .notInstalled, .notInstalled], 
                [.installing(.downloading(progress: progress)), .notInstalled, .notInstalled],
                [.installing(.unarchiving), .notInstalled, .notInstalled],
                [.installing(.moving(destination: "/Applications/Xcode-0.0.0.app")), .notInstalled, .notInstalled],
                [.installing(.trashingArchive), .notInstalled, .notInstalled],
                [.installing(.checkingSecurity), .notInstalled, .notInstalled],
                [.installing(.finishing), .notInstalled, .notInstalled],
                [.installed(Path("/Applications/Xcode-0.0.0.app")!), .notInstalled, .notInstalled]
            ]
        )
    }

    private static func downloadableRuntime() throws -> DownloadableRuntime {
        let json = """
        {
          "category": "simulator",
          "simulatorVersion": {
            "buildUpdate": "20A360",
            "version": "16.0"
          },
          "source": "https://example.com/iOS_16_Runtime.dmg",
          "architectures": null,
          "dictionaryVersion": 1,
          "contentType": "diskImage",
          "platform": "com.apple.platform.iphoneos",
          "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-16-0",
          "version": "16.0",
          "fileSize": 42,
          "hostRequirements": null,
          "name": "iOS 16.0",
          "authentication": null
        }
        """
        return try JSONDecoder().decode(DownloadableRuntime.self, from: Data(json.utf8))
    }

    private static func downloadResult(for availableXcode: AvailableXcode) -> (saveLocation: URL, response: URLResponse) {
        (
            saveLocation: (Path.xcodesApplicationSupport/"Xcode-\(availableXcode.version).xip").url,
            response: HTTPURLResponse(url: availableXcode.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    private static func runtimeService(
        deleteRuntimeOutput: @escaping @Sendable (String) async throws -> ProcessOutput
    ) -> RuntimeService {
        RuntimeService(
            loadData: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            contentsAtPath: { _ in
                Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>images</key>
                    <array/>
                </dict>
                </plist>
                """.utf8)
            },
            installedRuntimesOutput: {
                ProcessOutput(status: 0, out: "{}", err: "")
            },
            installRuntimeImageOutput: { _ in
                ProcessOutput(status: 0, out: "", err: "")
            },
            mountDMGOutput: { _ in
                ProcessOutput(status: 0, out: "", err: "")
            },
            unmountDMGOutput: { _ in
                ProcessOutput(status: 0, out: "", err: "")
            },
            deleteRuntimeOutput: deleteRuntimeOutput
        )
    }
    
    func test_Install_FullHappyPath_XcodeReleases() async throws {
        // Available xcode has build identifier
        subject.allXcodes = [
            .init(version: Version("0.0.0+ABC123")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.1+DEF456")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.2+GHI789")!, installState: .notInstalled, selected: false, icon: nil)
        ]
        
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        Xcodes.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(resultCode: 0, resultsString: nil, downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip", fileSize: 9494944)], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (
                    data: downloadsData,
                    response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }

            return (
                data: Data(),
                response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        Current.network.downloadTaskAsync = { url, saveLocation, _ in
            return (
                progress,
                Task {
                    await Task.yield()
                    await MainActor.run {
                        for i in 0...100 {
                            progress.completedUnitCount = Int64(i)
                        }
                    }
                    return (
                        saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    )
                }
            )
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeTeamIdentifier)
                        Authority=\(XcodeCertificateAuthority[0])
                        Authority=\(XcodeCertificateAuthority[1])
                        Authority=\(XcodeCertificateAuthority[2])
                        """)
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        let allXcodeInstallStates = try await recordAllXcodeInstallStates {
            _ = try await subject.installAsync(
                .version(AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)),
                downloader: .urlSession,
                attemptNumber: 0
            )
        }

        XCTAssertEqual(
            allXcodeInstallStates,
            [
                [XcodeInstallState.notInstalled, .notInstalled, .notInstalled], 
                [.installing(.downloading(progress: progress)), .notInstalled, .notInstalled],
                [.installing(.unarchiving), .notInstalled, .notInstalled],
                [.installing(.moving(destination: "/Applications/Xcode-0.0.0.app")), .notInstalled, .notInstalled],
                [.installing(.trashingArchive), .notInstalled, .notInstalled],
                [.installing(.checkingSecurity), .notInstalled, .notInstalled],
                [.installing(.finishing), .notInstalled, .notInstalled],
                [.installed(Path("/Applications/Xcode-0.0.0.app")!), .notInstalled, .notInstalled]
            ]
        )
    }

    func test_Install_NotEnoughFreeSpace() async throws {
        Current.shell.unxip = { _ in
            throw ProcessExecutionError(
                    process: Process(),
                    standardOutput: "xip: signing certificate was \"Development Update\" (validation not attempted)", 
                    standardError: "xip: error: The archive “Xcode-12.4.0-Release.Candidate+12D4e.xip” can’t be expanded because the selected volume doesn’t have enough free space."
            )
        }
        let archiveURL = URL(fileURLWithPath: "/Users/user/Library/Application Support/Xcode-0.0.0.xip")
        
        do {
            _ = try await subject.installArchivedXcodeAsync(
                AvailableXcode(
                    version: Version("0.0.0")!,
                    url: URL(string: "https://developer.apple.com")!,
                    filename: "Xcode-0.0.0.xip",
                    releaseDate: nil
                ),
                at: archiveURL
            )
            XCTFail()
        } catch let error as InstallationError {
            XCTAssertEqual(
                error,
                InstallationError.notEnoughFreeSpaceToExpandArchive(archivePath: Path(url: archiveURL)!, 
                                                                    version: Version("0.0.0")!)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func recordAllXcodeInstallStates(during operation: () async throws -> Void) async throws -> [[XcodeInstallState]] {
        var states: [[XcodeInstallState]] = []
        var cancellable: AnyCancellable?
        cancellable = subject.$allXcodes.sink { xcodes in
            states.append(xcodes.map(\.installState))
        }
        defer { cancellable?.cancel() }

        try await operation()
        return states
    }
}

private extension HTTPCookie {
    static func xcodesTestCookie(name: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .domain: "developer.apple.com",
            .path: "/",
            .name: name,
            .value: "test-cookie",
            .secure: "TRUE",
            .expires: Date.distantFuture
        ]))
    }
}
