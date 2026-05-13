import Foundation
import os.log

class XPCDelegate: NSObject, NSXPCListenerDelegate, HelperXPCProtocol {
    private let xcodeValidator = XcodeBundleValidator()
    private let commandTimeout: TimeInterval = 300

    // MARK: - NSXPCListenerDelegate

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard ConnectionVerifier.isValid(connection: newConnection) else { return false }

        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - HelperXPCProtocol

    func getVersion(completion: @escaping (String) -> Void) {
        Logger.xpcDelegate.info("\(#function)")
        completion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }

    func xcodeSelect(absolutePath: String, completion: @escaping (Error?) -> Void) {
        Logger.xpcDelegate.info("\(#function)")

        let validationResult: XcodeBundleValidationResult
        do {
            validationResult = try xcodeValidator.validate(absolutePath: absolutePath)
        } catch {
            completion(XPCDelegateError(.invalidXcodePath))
            return
        }

        run(
            url: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-s", validationResult.bundleURL.path],
            timeout: commandTimeout,
            completion: completion
        )
    }

    func devToolsSecurityEnable(completion: @escaping (Error?) -> Void) {
        run(
            url: URL(fileURLWithPath: "/usr/sbin/DevToolsSecurity"),
            arguments: ["-enable"],
            timeout: commandTimeout,
            completion: completion
        )
    }

    func addStaffToDevelopersGroup(completion: @escaping (Error?) -> Void) {
        run(
            url: URL(fileURLWithPath: "/usr/sbin/dseditgroup"),
            arguments: ["-o", "edit", "-t", "group", "-a", "staff", "_developer"],
            timeout: commandTimeout,
            completion: completion
        )
    }

    func acceptXcodeLicense(absoluteXcodePath: String, completion: @escaping (Error?) -> Void) {
        let validationResult: XcodeBundleValidationResult
        do {
            validationResult = try xcodeValidator.validate(absolutePath: absoluteXcodePath)
        } catch {
            completion(XPCDelegateError(.invalidXcodePath))
            return
        }

        run(
            url: validationResult.xcodebuildURL,
            arguments: ["-license", "accept"],
            timeout: commandTimeout,
            completion: completion
        )
    }

    func runFirstLaunch(absoluteXcodePath: String, completion: @escaping (Error?) -> Void) {
        let validationResult: XcodeBundleValidationResult
        do {
            validationResult = try xcodeValidator.validate(absolutePath: absoluteXcodePath)
        } catch {
            completion(XPCDelegateError(.invalidXcodePath))
            return
        }

        run(
            url: validationResult.xcodebuildURL,
            arguments: ["-runFirstLaunch"],
            timeout: commandTimeout,
            completion: completion
        )
    }
}

// MARK: - Run

private func run(url: URL, arguments: [String], timeout: TimeInterval, completion: @escaping (Error?) -> Void) {
    Logger.xpcDelegate.info("Run executable: \(url), arguments: \(arguments.joined(separator: ", "))")

    let process = Process()
    process.executableURL = url
    process.arguments = arguments

    let processFinished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        processFinished.signal()
    }

    do {
        try process.run()
    } catch {
        completion(error)
        return
    }

    let deadline = DispatchTime.now() + timeout
    guard processFinished.wait(timeout: deadline) == .success else {
        process.terminate()
        completion(XPCDelegateError(.commandTimedOut))
        return
    }

    guard process.terminationStatus == 0 else {
        completion(XPCDelegateError(.commandFailed))
        return
    }

    completion(nil)
}

// MARK: - Errors

struct XPCDelegateError: CustomNSError {
    enum Code: Int {
        case invalidXcodePath
        case commandFailed
        case commandTimedOut
    }

    let code: Code

    init(_ code: Code) {
        self.code = code
    }

    // MARK: - CustomNSError

    static var errorDomain: String {
        "XPCDelegateError"
    }

    var errorCode: Int {
        code.rawValue
    }

    var errorUserInfo: [String: Any] {
        switch code {
        case .invalidXcodePath:
            [
                NSLocalizedDescriptionKey: "Invalid Xcode path.",
                NSLocalizedFailureReasonErrorKey: "Xcode path must be a valid, signed Xcode app bundle."
            ]
        case .commandFailed:
            [
                NSLocalizedDescriptionKey: "Privileged helper command failed.",
                NSLocalizedFailureReasonErrorKey: "The command exited with a non-zero status."
            ]
        case .commandTimedOut:
            [
                NSLocalizedDescriptionKey: "Privileged helper command timed out.",
                NSLocalizedFailureReasonErrorKey: "The command did not finish before the timeout."
            ]
        }
    }
}
