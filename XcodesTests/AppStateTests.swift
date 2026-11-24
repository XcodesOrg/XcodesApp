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

    func test_Select_HelperFailureOffersTerminalCommand() async throws {
        let path = try XCTUnwrap(Path("/Applications/Xcode 27's Preview.app"))
        let xcode = Xcode(version: Version("27.0.0")!, installState: .installed(path), selected: false, icon: nil)
        subject.helperInstallState = .installed
        subject.onSelectActionType = .none
        Current.helper.switchXcodePathAsync = { _ in throw HelperClientError.message("Helper unavailable") }

        subject.select(xcode: xcode, shouldPrepareUserForHelperInstallation: false)
        let task = try XCTUnwrap(subject.selectTask)
        await task.value

        guard case let .helperRecovery(recovery) = subject.presentedSheet else {
            return XCTFail("Expected helper recovery")
        }
        XCTAssertEqual(recovery.command, "sudo /usr/bin/xcode-select --switch '/Applications/Xcode 27'\"'\"'s Preview.app'")
        XCTAssertTrue(recovery.message.contains("Helper unavailable"))
        XCTAssertNil(subject.error)
        XCTAssertNil(subject.presentedAlert)
        XCTAssertNil(subject.selectedXcodePath)
    }

    func test_Select_HelperInstallFailureOffersTerminalCommand() async throws {
        let path = try XCTUnwrap(Path("/Applications/Xcode.app"))
        let xcode = Xcode(version: Version("27.0.0")!, installState: .installed(path), selected: false, icon: nil)
        subject.helperInstallState = .notInstalled
        Current.helper.install = { throw HelperClientError.message("Installation failed") }

        subject.select(xcode: xcode, shouldPrepareUserForHelperInstallation: false)
        let task = try XCTUnwrap(subject.selectTask)
        await task.value

        guard case let .helperRecovery(recovery) = subject.presentedSheet else {
            return XCTFail("Expected helper recovery")
        }
        XCTAssertEqual(recovery.command, HelperRecovery.selectCommand(path: path.string))
        XCTAssertTrue(recovery.message.contains("Installation failed"))
        XCTAssertNil(subject.presentedAlert)
    }

    func test_PostInstall_HelperFailureOffersOpeningInstalledXcode() async throws {
        subject.helperInstallState = .installed
        let xcode = InstalledXcode(path: Path("/Applications/Xcode Preview.app")!, version: Version("27.0.0")!)
        Current.helper.devToolsSecurityEnableAsync = { throw HelperClientError.message("Helper unavailable") }

        subject.performPostInstallSteps(for: xcode)
        let task = try XCTUnwrap(subject.postInstallTask)
        await task.value

        guard case let .postInstallFailed(installedXcode) = subject.presentedAlert else {
            return XCTFail("Expected an option to open Xcode")
        }
        XCTAssertEqual(installedXcode.path, xcode.path)
        XCTAssertEqual(installedXcode.version, xcode.version)
        XCTAssertNil(subject.error)
        XCTAssertNil(subject.presentedSheet)
    }

    func test_HelperRecovery_QuotedPathRoundTripsThroughShell() throws {
        let path = "/Applications/Xcode's $(touch /tmp/xcodes-should-not-exist) `whoami` \"Preview\".app"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' " + HelperRecovery.quote(path)]
        process.standardOutput = output
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: result, encoding: .utf8), path)
    }

    func test_InstallHelper_RetriesUntilNewlyInstalledHelperAnswers() async throws {
        subject.helperInstallState = .notInstalled
        subject.helperInstallRetryDelay = .zero
        let checks = AppStateTestsCounter()
        Current.helper.install = { }
        Current.helper.checkIfLatestHelperIsInstalledAsync = {
            // launchd hasn't started the helper for the first couple of checks
            checks.increment() >= 3
        }

        try await subject.installHelperIfNecessaryAsync()

        XCTAssertEqual(subject.helperInstallState, .installed)
        XCTAssertEqual(checks.value, 3)
    }

    func test_InstallHelper_ThrowsWithReasonWhenInstalledHelperIsUnreachable() async throws {
        subject.helperInstallState = .notInstalled
        subject.helperInstallRetryDelay = .zero
        Current.helper.install = { }
        Current.helper.checkIfLatestHelperIsInstalledAsync = {
            throw NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)
        }

        do {
            try await subject.installHelperIfNecessaryAsync()
            XCTFail("Expected an unreachable helper to throw")
        } catch let HelperClientError.unreachableAfterInstall(underlyingError) {
            XCTAssertEqual((underlyingError as NSError?)?.code, NSXPCConnectionInvalid)
        }
        XCTAssertEqual(subject.helperInstallState, .notInstalled)
    }

    func test_PostInstallStepsError_IncludesUnderlyingReason() {
        let error = InstallationError.postInstallStepsNotPerformed(
            version: Version("27.2.0")!,
            helperInstallState: .notInstalled,
            reason: HelperClientError.unreachableAfterInstall(underlyingError: nil).localizedDescription
        )

        XCTAssertTrue(error.errorDescription?.contains(localizeString("HelperClient.error.UnreachableAfterInstall")) == true)
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

    func test_Select_MarksXcodeInstalledSinceLastScanAsSelected() async throws {
        subject.helperInstallState = .installed
        let installedPath = try XCTUnwrap(Path("/Applications/Xcode-27.2.0.app"))
        let version = try XCTUnwrap(Version("27.2.0"))
        let installedXcode = InstalledXcode(path: installedPath, version: version)
        let developerPath = (installedPath/"Contents/Developer").string
        subject.availableXcodes = [
            AvailableXcode(version: version, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        ]
        subject.allXcodes[0].installState = .installed(installedPath)
        Current.files.installedXcodes = { _ in [installedXcode] }
        Current.shell.xcodeSelectPrintPath = {
            ProcessOutput(status: 0, out: developerPath, err: "")
        }

        subject.select(xcode: subject.allXcodes[0], shouldPrepareUserForHelperInstallation: false)
        let selectTask = try XCTUnwrap(subject.selectTask)
        await selectTask.value

        XCTAssertEqual(subject.allXcodes[0].installState, .installed(installedPath))
        XCTAssertTrue(subject.allXcodes[0].selected)
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
            "remove:\(xcode.installedPath!.string)", "refreshInstalled", "refreshSelection"
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

    func test_Uninstall_DoesNotShowRemovedXcodeAsInstalledAgain() async throws {
        let installedPath = try XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))
        let version = try XCTUnwrap(Version("0.0.0"))
        let installedXcode = InstalledXcode(path: installedPath, version: version)
        subject.availableXcodes = [
            AvailableXcode(version: version, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        ]
        Current.files.installedXcodes = { _ in [installedXcode] }
        await subject.updateInstalledXcodesAsync()
        Current.files.installedXcodes = { _ in [] }
        Current.shell.xcodeSelectPrintPath = {
            ProcessOutput(status: 0, out: "", err: "")
        }

        let allXcodeInstallStates = try await recordAllXcodeInstallStates {
            subject.uninstall(xcode: subject.allXcodes[0])
            let uninstallTask = try XCTUnwrap(subject.uninstallTask)
            await uninstallTask.value
        }

        XCTAssertEqual(
            allXcodeInstallStates,
            [
                [XcodeInstallState.installed(installedPath)],
                [.uninstalling(installedPath)],
                [.notInstalled],
                [.notInstalled]
            ]
        )
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
                    "trash:\(xcode.installedPath!.string)", "refreshInstalled", "refreshSelection"
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
            XCTAssertEqual(operations.read { $0 }, deletion + ["refreshInstalled", "refreshSelection"])
            assertUninstallSucceeded()
        }
    }

    func test_UninstallWithPlatforms_PermanentRemovesOriginalBundle() async throws {
        let (xcode, operations) = makeUninstallFixture(useHelper: false)

        let task = try XCTUnwrap(subject.uninstall(xcode: xcode, permanently: true, removingRuntimes: []))
        await task.value

        XCTAssertEqual(operations.read { $0 }, [
            "remove:\(xcode.installedPath!.string)", "refreshInstalled", "refreshSelection"
        ])
        assertUninstallSucceeded()
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
                if permanently && useHelper {
                    XCTAssertNil(subject.error)
                    XCTAssertNil(subject.presentedAlert)
                    guard case let .helperRecovery(recovery) = subject.presentedSheet else {
                        return XCTFail("Expected helper recovery sheet")
                    }
                    XCTAssertEqual(recovery.title, localizeString("Alert.Uninstall.Error.Title"))
                    XCTAssertEqual(recovery.message, failure.legibleLocalizedDescription)
                    XCTAssertEqual(recovery.command, "sudo /bin/rm -rf " + HelperRecovery.quote(xcode.installedPath!.string))
                } else {
                    XCTAssertEqual(subject.error as NSError?, failure)
                    XCTAssertNil(subject.presentedSheet)
                    guard case let .generic(title, message) = subject.presentedAlert else {
                        return XCTFail("Expected generic uninstall error alert")
                    }
                    XCTAssertEqual(title, localizeString("Alert.Uninstall.Error.Title"))
                    XCTAssertEqual(message, failure.legibleLocalizedDescription)
                }
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
                "delete:\(firstXcode.installedPath!.string)", "refreshInstalled", "refreshSelection"
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

    func test_RestoreAuthenticationStateIfNeeded_NetworkFailureDoesNotRetryLogin() async throws {
        let didReadPassword = TestLockedBox(false)
        Current.defaults.string = { _ in "jane@example.com" }
        Current.keychain.getString = { _ in
            didReadPassword.withValue { $0 = true }
            return "password"
        }
        Current.network.validateSessionAsync = { throw URLError(.notConnectedToInternet) }

        do {
            try await subject.restoreAuthenticationStateIfNeeded()
            XCTFail("Expected the network error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        XCTAssertFalse(didReadPassword.read { $0 })
        XCTAssertNil(subject.authError)
    }

    func test_SignIn_NetworkFailurePreservesSavedCredentials() async throws {
        let removedCredentials = TestLockedBox<[String]>([])
        Current.keychain.remove = { key in removedCredentials.withValue { $0.append(key) } }
        Current.defaults.removeObject = { key in removedCredentials.withValue { $0.append(key) } }
        Current.network.session = MockURLProtocol.session { _ in throw URLError(.timedOut) }

        do {
            _ = try await subject.signInAsync(username: "jane@example.com", password: "password")
            XCTFail("Expected authentication to fail")
        } catch {
            XCTAssertNotNil(subject.authError)
        }

        XCTAssertTrue(removedCredentials.read { $0.isEmpty })
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

    func test_Install_CachedAEAWithExperimentalUnxipEnabled() async throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["XCODES_AEA_FIXTURE"] else {
            throw XCTSkip("Set XCODES_AEA_FIXTURE to an Apple Xcode AEA archive to run this smoke test.")
        }
        let fixture = URL(fileURLWithPath: fixturePath)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Xcodes-AEA-test-\(UUID())", isDirectory: true)
        let cache = root.appendingPathComponent("Archive Cache", isDirectory: true)
        let destination = root.appendingPathComponent("Install Destination", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        let version = try XCTUnwrap(Version(xcodeVersion: "27.3 beta"))
        let archive = cache.appendingPathComponent("Xcode-\(version).aea")
        try FileManager.default.copyItem(at: fixture, to: archive)
        let xcode = AvailableXcode(
            version: version,
            url: URL(string: "https://developer.apple.com/Xcode_27.3_beta.aea")!,
            filename: fixture.lastPathComponent,
            releaseDate: nil
        )

        Current.defaults.string = { key in
            switch key {
            case "localPath": cache.path
            case "installPath": destination.path
            default: nil
            }
        }
        Current.files = Files(trashItem: { url in
            try FileManager.default.removeItem(at: url)
            return url
        })
        Current.network.downloadTaskAsync = { _, _, _ in
            XCTFail("The app should reuse the cached AEA")
            return (Progress(), Task { throw URLError(.resourceUnavailable) })
        }
        Current.shell.unxip = { _ in throw XcodesKitError("AEA must bypass xip") }
        Current.shell.unxipExperiment = { _ in throw XcodesKitError("AEA must bypass experimental unxip") }
        Current.shell.spctlAssess = XcodesShell().spctlAssess
        Current.shell.codesignVerify = XcodesShell().codesignVerify
        subject.unxipExperiment = true
        subject.helperInstallState = .installed

        let installed = try await subject.installAsync(.version(xcode), downloader: .urlSession, attemptNumber: 0)
        let expected = destination.appendingPathComponent("Xcode-\(version.descriptionWithoutBuildMetadata).app")
        XCTAssertEqual(installed.path.string, expected.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    func test_Install_DownloadedAEAUsingURLSession() async throws {
        try await installFromArchiveSmokeServer(format: "aea", downloader: .urlSession)
    }

    func test_Install_DownloadedXIPUsingAria2() async throws {
        try await installFromArchiveSmokeServer(format: "xip", downloader: .aria2)
    }

    private func installFromArchiveSmokeServer(format: String, downloader: Downloader) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["XCODES_ARCHIVE_SMOKE_URL"].flatMap(URL.init(string:)),
              server.scheme == "http", server.host == "127.0.0.1" else {
            throw XCTSkip("Set XCODES_ARCHIVE_SMOKE_URL to the loopback fixture server for this smoke test.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Xcodes-Download-test-\(UUID())", isDirectory: true)
        let cache = root.appendingPathComponent("Archive Cache", isDirectory: true)
        let destination = root.appendingPathComponent("Install Destination", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        let version = try XCTUnwrap(Version(xcodeVersion: "27.3 beta"))
        let filename = "Xcode_27.3_beta.\(format)"
        let url = server.appendingPathComponent("app/\(filename)")
        let archive = cache.appendingPathComponent("Xcode-\(version).\(url.pathExtension)")
        let xcode = AvailableXcode(version: version, url: url, filename: filename, releaseDate: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))

        Current.defaults.string = { key in
            switch key {
            case "localPath": cache.path
            case "installPath": destination.path
            default: nil
            }
        }
        Current.files = Files(trashItem: { url in
            XCTAssertEqual(url.path, archive.path)
            try FileManager.default.removeItem(at: url)
            return url
        })
        Current.network = Network(session: URLSession(configuration: .ephemeral), validateSessionAsync: { .unauthenticated })
        if url.pathExtension == "aea" {
            Current.shell.unxip = { _ in throw XcodesKitError("AEA must bypass xip") }
            Current.shell.unxipExperiment = { _ in throw XcodesKitError("AEA must bypass experimental unxip") }
        } else {
            Current.shell.unxip = XcodesShell().unxip
        }
        Current.shell.spctlAssess = XcodesShell().spctlAssess
        Current.shell.codesignVerify = XcodesShell().codesignVerify
        subject.unxipExperiment = url.pathExtension == "aea"
        subject.helperInstallState = .installed

        let expectedApp = destination.appendingPathComponent("Xcode-\(version.descriptionWithoutBuildMetadata).app")
        let expectDamagedXIP = url.pathExtension == "xip" && environment["XCODES_ARCHIVE_SMOKE_EXPECT_DAMAGED_XIP"] == "1"
        do {
            let installed = try await subject.installAsync(.version(xcode), downloader: downloader, attemptNumber: 0)
            XCTAssertFalse(expectDamagedXIP, "Expected the damaged XIP to be rejected")
            XCTAssertEqual(installed.path.string, expectedApp.path)
            XCTAssertEqual(installed.version.buildMetadataIdentifiers, ["27C5020n"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        } catch let error as InstallationError {
            guard expectDamagedXIP, case let .damagedXIP(rejectedArchive) = error else { throw error }
            XCTAssertEqual(rejectedArchive.path, archive.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: expectedApp.path))
        }
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

private final class AppStateTestsCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
