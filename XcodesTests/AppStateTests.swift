import Combine
import Cocoa
import AsyncNetworkService
@preconcurrency import Path
import class SwiftUI.NSHostingView
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

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private nonisolated(unsafe) static var handler: Handler?

    static func session(handler: @escaping Handler) -> URLSession {
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension NSView {
    func recursiveSubviews<T: NSView>(ofType type: T.Type) -> [T] {
        subviews.compactMap { $0 as? T } + subviews.flatMap { $0.recursiveSubviews(ofType: type) }
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

    func test_InstallError_Network401IsUnauthorized() {
        let error = NetworkError.non200StatusCode(statusCode: 401, data: Data())

        XCTAssertTrue(AppState.isUnauthorizedInstallError(error))
    }

    func test_InstallError_OtherNetworkStatusIsNotUnauthorized() {
        let error = NetworkError.non200StatusCode(statusCode: 500, data: Data())

        XCTAssertFalse(AppState.isUnauthorizedInstallError(error))
    }

    func test_PinCodeTextView_MarksDigitFieldsAsOneTimeCode() {
        let pinCodeTextView = PinCodeTextView(numberOfDigits: 6, itemSpacing: 10)

        let editableTextFields = pinCodeTextView.recursiveSubviews(ofType: NSTextField.self)
            .filter(\.isEditable)

        XCTAssertEqual(editableTextFields.count, 6)
        XCTAssertTrue(editableTextFields.allSatisfy { $0.contentType == .oneTimeCode })
    }

    func test_PinCodeTextView_PastedCodeIsDistributedAcrossDigitFields() {
        let pinCodeTextView = PinCodeTextView(numberOfDigits: 6, itemSpacing: 10)
        var changedCodes: [String] = []
        pinCodeTextView.codeDidChange = { changedCodes.append($0) }

        let inputTextField = pinCodeTextView.recursiveSubviews(ofType: NSTextField.self)
            .first { $0.isEditable }!
        inputTextField.stringValue = "123 456"

        pinCodeTextView.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: inputTextField))

        XCTAssertEqual(changedCodes.last, "123456")
    }

    func test_ChoosePhoneNumberForSMS_WithOneTrustedPhoneNumberRequestsSMS() async throws {
        let trustedPhoneNumber = AuthOptionsResponse.TrustedPhoneNumber(id: 7, numberWithDialCode: "(•••) •••-••90")
        let authOptions = AuthOptionsResponse(
            trustedPhoneNumbers: [trustedPhoneNumber],
            trustedDevices: nil,
            securityCode: .init(length: 6)
        )
        let sessionData = AppleSessionData(serviceKey: "service-key", sessionID: "session-id", scnt: "scnt")
        Current.network = Network(session: MockURLProtocol.session { request in
            XCTAssertEqual(request.url?.absoluteString, "https://idmsa.apple.com/appleauth/auth/verify/phone")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Apple-ID-Session-Id"), "session-id")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Apple-Widget-Key"), "service-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "scnt"), "scnt")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        })

        subject.choosePhoneNumberForSMS(authOptions: authOptions, sessionData: sessionData)
        for _ in 0..<100 where subject.presentedSheet == nil && subject.authError == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNil(subject.authError)
        guard case let .twoFactor(secondFactorData) = subject.presentedSheet else {
            XCTFail("Expected the SMS code-entry sheet to be presented")
            return
        }
        XCTAssertEqual(secondFactorData.option, .smsSent(trustedPhoneNumber))
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

    func test_CreateSymbolicLink_UsesProvidedInstalledPath() async throws {
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

        await subject.createSymbolicLink(to: installedXcodePath)

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

    func test_UninstallAlert_PermanentDeletionResetsAfterCancelAndUsesRemoveWhenConfirmed() async throws {
        let (xcode, operations) = makeUninstallFixture(useHelper: false)
        let previousKeyWindow = NSApp.keyWindow
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainWindow().environmentObject(subject))
        defer {
            subject.xcodeBeingConfirmedForUninstallation = nil
            subject.uninstallTask?.cancel()
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
                sheet.orderOut(nil)
            }
            window.contentView = nil
            window.close()
            previousKeyWindow?.makeKey()
        }
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)

        func waitUntil(_ message: String, condition: @MainActor () -> Bool) async throws {
            for _ in 0..<200 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            _ = try XCTUnwrap(condition() ? true : nil, message)
        }

        let checkboxTitle = localizeString("Alert.Uninstall.DeletePermanently")
        func sheetButton(titled title: String) -> NSButton? {
            window.attachedSheet?.contentView?.recursiveSubviews(ofType: NSButton.self)
                .first { $0.title == title }
        }

        subject.xcodeBeingConfirmedForUninstallation = xcode
        try await waitUntil("Expected the native uninstall sheet and suppression checkbox") {
            sheetButton(titled: checkboxTitle) != nil
        }
        let firstCheckbox = try XCTUnwrap(sheetButton(titled: checkboxTitle))
        XCTAssertEqual(firstCheckbox.state, .off)
        firstCheckbox.performClick(nil)
        XCTAssertEqual(firstCheckbox.state, .on)
        let cancelButton = try XCTUnwrap(sheetButton(titled: localizeString("Cancel")))
        cancelButton.performClick(nil)
        try await waitUntil("Expected Cancel to dismiss the sheet and clear its target") {
            window.attachedSheet == nil && self.subject.xcodeBeingConfirmedForUninstallation == nil
        }
        XCTAssertTrue(operations.read { $0.isEmpty })
        XCTAssertNil(subject.uninstallTask)

        subject.xcodeBeingConfirmedForUninstallation = xcode
        try await waitUntil("Expected the uninstall sheet to reopen for the same Xcode") {
            sheetButton(titled: checkboxTitle) != nil
        }
        let reopenedCheckbox = try XCTUnwrap(sheetButton(titled: checkboxTitle))
        XCTAssertEqual(reopenedCheckbox.state, .off)
        reopenedCheckbox.performClick(nil)
        XCTAssertEqual(reopenedCheckbox.state, .on)
        let uninstallButton = try XCTUnwrap(sheetButton(titled: localizeString("Uninstall")))
        uninstallButton.performClick(nil)
        try await waitUntil("Expected the mocked permanent uninstall to finish and dismiss its sheet") {
            !operations.read { $0.isEmpty }
                && self.subject.uninstallTask == nil
                && self.subject.xcodeBeingConfirmedForUninstallation == nil
                && window.attachedSheet == nil
        }

        XCTAssertEqual(operations.read { $0 }, [
            "remove:\(xcode.installedPath!.string)", "refreshSelection", "refreshInstalled"
        ])
        assertUninstallSucceeded()
    }

    func test_Uninstall_MissingXcodePresentsFileNotFoundError() async throws {
        let missingPath = try XCTUnwrap(Path("/Applications/Xcode-Missing.app"))
        let xcode = Xcode(version: Version("15.0.0")!, installState: .installed(missingPath), selected: false, icon: nil)
        let didTryToTrashItem = TestLockedBox(false)
        Current.files.contentsAtPath = { _ in nil }
        Current.files.trashItem = { _ in
            didTryToTrashItem.withValue { $0 = true }
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash")
        }

        subject.uninstall(xcode: xcode)
        let uninstallTask = try XCTUnwrap(subject.uninstallTask)
        await uninstallTask.value

        guard case let .generic(title, message) = subject.presentedAlert else {
            return XCTFail("Expected generic uninstall error alert")
        }
        XCTAssertEqual(title, localizeString("Alert.Uninstall.Error.Title"))
        XCTAssertEqual(
            message,
            String(format: localizeString("Alert.Uninstall.Error.Message.FileNotFound"), missingPath.string)
        )
        XCTAssertFalse(didTryToTrashItem.read { $0 })
    }

    func test_Uninstall_RefreshesInstalledXcodeList() async throws {
        let installedPath = try XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))
        let version = try XCTUnwrap(Version("0.0.0"))
        subject.availableXcodes = [
            AvailableXcode(version: version, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        ]
        subject.allXcodes = [
            Xcode(version: version, installState: .installed(installedPath), selected: true, icon: nil)
        ]
        Current.files.installedXcodes = { _ in [] }
        Current.shell.xcodeSelectPrintPath = {
            ProcessOutput(status: 0, out: "", err: "")
        }

        subject.uninstall(xcode: subject.allXcodes[0])
        let uninstallTask = try XCTUnwrap(subject.uninstallTask)
        await uninstallTask.value

        XCTAssertEqual(subject.allXcodes[0].installState, .notInstalled)
    }

    func test_Uninstall_DefaultAndExplicitTrashUseCurrentUserWithEitherHelperPreference() async throws {
        for useHelper in [false, true] {
            for useDefault in [false, true] {
                let (xcode, operations) = makeUninstallFixture(useHelper: useHelper)

                if useDefault {
                    subject.uninstall(xcode: xcode)
                } else {
                    subject.uninstall(xcode: xcode, permanently: false)
                }
                XCTAssertEqual(subject.allXcodes[0].installState, .uninstalling(xcode.installedPath!))
                let task = try XCTUnwrap(subject.uninstallTask)
                await task.value

                XCTAssertEqual(operations.read { $0 }, [
                    "trash:\(xcode.installedPath!.string)", "refreshSelection", "refreshInstalled"
                ])
                assertUninstallSucceeded()
            }
        }
    }

    func test_Uninstall_PermanentRemovesOriginalBundleWithEitherHelperPreference() async throws {
        for useHelper in [false, true] {
            let (xcode, operations) = makeUninstallFixture(useHelper: useHelper)

            subject.uninstall(xcode: xcode, permanently: true)
            XCTAssertEqual(subject.allXcodes[0].installState, .uninstalling(xcode.installedPath!))
            let task = try XCTUnwrap(subject.uninstallTask)
            await task.value

            let deletion = useHelper
                ? ["installHelper", "checkHelper", "helperRemove:\(xcode.installedPath!.string)"]
                : ["remove:\(xcode.installedPath!.string)"]
            XCTAssertEqual(operations.read { $0 }, deletion + ["refreshSelection", "refreshInstalled"])
            assertUninstallSucceeded()
        }
    }

    func test_Uninstall_FailureRestoresInstalledStateAndCleansUpTask() async throws {
        for useHelper in [false, true] {
            for permanently in [false, true] {
                let failure = NSError(domain: "UninstallTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deletion failed"])
                let (xcode, operations) = makeUninstallFixture(useHelper: useHelper, failure: failure)

                subject.uninstall(xcode: xcode, permanently: permanently)
                let task = try XCTUnwrap(subject.uninstallTask)
                await task.value

                let deletion: [String]
                if permanently && useHelper {
                    deletion = ["installHelper", "checkHelper", "helperRemove:\(xcode.installedPath!.string)"]
                } else {
                    deletion = ["\(permanently ? "remove" : "trash"):\(xcode.installedPath!.string)"]
                }
                XCTAssertEqual(operations.read { $0 }, deletion)
                XCTAssertEqual(subject.allXcodes[0].installState, xcode.installState)
                XCTAssertEqual(subject.error as NSError?, failure)
                guard case let .generic(title, message) = subject.presentedAlert else {
                    return XCTFail("Expected generic uninstall error alert")
                }
                XCTAssertEqual(title, localizeString("Alert.Uninstall.Error.Title"))
                XCTAssertEqual(message, failure.localizedDescription)
                XCTAssertNil(subject.uninstallTask)
                XCTAssertNil(subject.uninstallTaskID)
            }
        }
    }

    func test_Uninstall_MissingMetadataPreventsAllDeletionAndHelperOperations() async throws {
        for useHelper in [false, true] {
            for permanently in [false, true] {
                let (xcode, operations) = makeUninstallFixture(useHelper: useHelper)
                Current.files.contentsAtPath = { _ in nil }

                subject.uninstall(xcode: xcode, permanently: permanently)
                let task = try XCTUnwrap(subject.uninstallTask)
                await task.value

                XCTAssertTrue(operations.read { $0.isEmpty })
                XCTAssertEqual(subject.allXcodes[0].installState, xcode.installState)
                guard case let .fileNotFound(path) = subject.error as? FileError else {
                    return XCTFail("Expected file-not-found error")
                }
                XCTAssertEqual(path, xcode.installedPath!.string)
                XCTAssertNotNil(subject.presentedAlert)
                XCTAssertNil(subject.uninstallTask)
                XCTAssertNil(subject.uninstallTaskID)
            }
        }
    }

    func test_Uninstall_EarlierLocalDeletionRefreshesAfterLaterUninstallFails() async throws {
        for permanently in [false, true] {
            let (firstXcode, operations) = makeUninstallFixture(useHelper: false)
            let secondPath = Path("/Applications/Xcode-1.0.0.app")!
            let secondVersion = Version("1.0.0")!
            let secondXcode = Xcode(version: secondVersion, installState: .installed(secondPath), selected: false, icon: nil)
            let remainingXcode = InstalledXcode(path: secondPath, version: secondVersion)
            subject.availableXcodes.append(
                AvailableXcode(version: secondVersion, url: URL(string: "https://apple.com/second.xip")!, filename: "second.xip", releaseDate: nil)
            )
            subject.allXcodes = [firstXcode, secondXcode]

            let contentsAtPath = Current.files.contentsAtPath
            Current.files.contentsAtPath = { path in
                path.hasPrefix(secondPath.string + "/") ? nil : contentsAtPath(path)
            }
            Current.files.installedXcodes = { _ in
                operations.withValue { $0.append("refreshInstalled") }
                return [remainingXcode]
            }
            Current.shell.xcodeSelectPrintPath = {
                operations.withValue { $0.append("refreshSelection") }
                return ProcessOutput(status: 0, out: secondPath.string, err: "")
            }

            let deletionStarted = AsyncStream<Void>.makeStream()
            let allowDeletionToFinish = DispatchSemaphore(value: 0)
            defer { allowDeletionToFinish.signal() }
            let delete: @Sendable (URL) -> Void = { url in
                XCTAssertFalse(Thread.isMainThread)
                operations.withValue { $0.append("delete:\(url.path)") }
                deletionStarted.continuation.yield(())
                deletionStarted.continuation.finish()
                XCTAssertEqual(allowDeletionToFinish.wait(timeout: .now() + 10), .success)
            }
            Current.files.removeItem = { delete($0) }
            Current.files.trashItem = {
                delete($0)
                return URL(fileURLWithPath: "/Users/test/.Trash/Xcode-0.0.0.app")
            }

            subject.uninstall(xcode: firstXcode, permanently: permanently)
            let firstTask = try XCTUnwrap(subject.uninstallTask)
            var started = deletionStarted.stream.makeAsyncIterator()
            _ = await started.next()

            subject.uninstall(xcode: secondXcode, permanently: permanently)
            let secondTask = try XCTUnwrap(subject.uninstallTask)
            await secondTask.value

            XCTAssertFalse(firstTask.isCancelled)
            XCTAssertEqual(subject.allXcodes.first { $0.id == firstXcode.id }?.installState, .uninstalling(firstXcode.installedPath!))
            XCTAssertEqual(subject.allXcodes.first { $0.id == secondXcode.id }?.installState, .installed(secondPath))
            guard case let .fileNotFound(path) = subject.error as? FileError else {
                allowDeletionToFinish.signal()
                await firstTask.value
                return XCTFail("Expected the second uninstall to fail metadata validation")
            }
            XCTAssertEqual(path, secondPath.string)
            XCTAssertNil(subject.uninstallTask)
            XCTAssertNil(subject.uninstallTaskID)

            allowDeletionToFinish.signal()
            await firstTask.value

            XCTAssertEqual(operations.read { $0 }, [
                "delete:\(firstXcode.installedPath!.string)", "refreshSelection", "refreshInstalled"
            ])
            XCTAssertEqual(subject.allXcodes.first { $0.id == firstXcode.id }?.installState, .notInstalled)
            XCTAssertEqual(subject.allXcodes.first { $0.id == secondXcode.id }?.installState, .installed(secondPath))
            XCTAssertEqual(subject.selectedXcodePath, secondPath.string)
            XCTAssertEqual(subject.allXcodes.first { $0.id == secondXcode.id }?.selected, true)
            XCTAssertNil(subject.uninstallTask)
            XCTAssertNil(subject.uninstallTaskID)
        }
    }

    private func makeUninstallFixture(
        useHelper: Bool,
        failure: NSError? = nil
    ) -> (Xcode, TestLockedBox<[String]>) {
        Current = .mock
        subject = AppState()
        subject.helperInstallState = .notInstalled
        let path = Path("/Applications/Xcode-0.0.0.app")!
        let version = Version("0.0.0")!
        let xcode = Xcode(version: version, installState: .installed(path), selected: true, icon: nil)
        subject.availableXcodes = [
            AvailableXcode(version: version, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        ]
        subject.selectedXcodePath = path.string
        subject.allXcodes = [xcode]
        let operations = TestLockedBox<[String]>([])
        Current.defaults.bool = { key in
            key == PreferenceKey.usePrivilegeHelperForFileOperations.rawValue ? useHelper : nil
        }
        Current.files.trashItem = { url in
            XCTAssertFalse(Thread.isMainThread)
            operations.withValue { $0.append("trash:\(url.path)") }
            if let failure { throw failure }
            return URL(fileURLWithPath: "/Users/test/.Trash/Xcode-0.0.0.app")
        }
        Current.files.removeItem = { url in
            XCTAssertFalse(Thread.isMainThread)
            operations.withValue { $0.append("remove:\(url.path)") }
            if let failure { throw failure }
        }
        Current.helper.install = {
            operations.withValue { $0.append("installHelper") }
        }
        Current.helper.checkIfLatestHelperIsInstalledAsync = {
            operations.withValue { $0.append("checkHelper") }
            return true
        }
        Current.helper.removeAsync = { path in
            operations.withValue { $0.append("helperRemove:\(path)") }
            if let failure { throw failure }
        }
        Current.shell.xcodeSelectPrintPath = {
            operations.withValue { $0.append("refreshSelection") }
            return ProcessOutput(status: 0, out: "", err: "")
        }
        Current.files.installedXcodes = { _ in
            operations.withValue { $0.append("refreshInstalled") }
            return []
        }
        return (xcode, operations)
    }

    private func assertUninstallSucceeded(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(subject.allXcodes[0].installState, .notInstalled, file: file, line: line)
        XCTAssertFalse(subject.allXcodes[0].selected, file: file, line: line)
        XCTAssertEqual(subject.selectedXcodePath, "", file: file, line: line)
        XCTAssertNil(subject.error, file: file, line: line)
        XCTAssertNil(subject.presentedAlert, file: file, line: line)
        XCTAssertNil(subject.uninstallTask, file: file, line: line)
        XCTAssertNil(subject.uninstallTaskID, file: file, line: line)
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

    func test_RestoreAuthenticationStateIfNeeded_UsesPersistedSession() async throws {
        let appleSession = try JSONDecoder().decode(
            AppleSession.self,
            from: Data(#"{"user":{"fullName":"Jane Developer"}}"#.utf8)
        )
        let expectedState = AuthenticationState.authenticated(appleSession)
        Current.defaults.string = { key in
            key == "username" ? "jane@example.com" : nil
        }
        Current.network.validateSessionAsync = { expectedState }

        try await subject.restoreAuthenticationStateIfNeeded()

        XCTAssertEqual(subject.authenticationState, expectedState)
    }

    func test_RestoreAuthenticationStateIfNeeded_SkipsValidationWithoutSavedUsername() async throws {
        let didValidate = TestLockedBox(false)
        Current.network.validateSessionAsync = {
            didValidate.withValue { $0 = true }
            return .unauthenticated
        }

        try await subject.restoreAuthenticationStateIfNeeded()

        XCTAssertFalse(didValidate.read { $0 })
        XCTAssertEqual(subject.authenticationState, .unauthenticated)
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
        Xcodes.Current.network.validateSessionAsync = { .unauthenticated }
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

    func test_InstallNotificationTitle_DoesNotDuplicateMajorVersion() {
        XCTAssertEqual(
            AppState.installNotificationTitle(for: Version(major: 27, minor: 0, patch: 0, prereleaseIdentifiers: ["beta", "4"])),
            "27.0 Beta 4"
        )
        XCTAssertEqual(
            AppState.installNotificationTitle(for: Version(major: 26, minor: 5, patch: 0)),
            "26.5"
        )
        // Stable release with patch
        XCTAssertEqual(
            AppState.installNotificationTitle(for: Version(major: 10, minor: 2, patch: 1)),
            "10.2.1"
        )
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
