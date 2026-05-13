import Foundation
import os.log
import Security
import ServiceManagement
import XcodesKit

@_silgen_name("SMJobBless")
@discardableResult
func legacySMJobBless(
    _ domain: CFString?,
    _ executableLabel: CFString,
    _ auth: AuthorizationRef?,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> Bool

actor HelperClient {
    private let installedHelperURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools")
        .appendingPathComponent(machServiceName)

    var connection: NSXPCConnection?

    func currentConnection() -> NSXPCConnection? {
        guard self.connection == nil else {
            return self.connection
        }

        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.invalidationHandler = {
            Task {
                self.clearConnection()
            }
        }

        self.connection = connection
        connection.resume()

        return self.connection
    }

    private func clearConnection() {
        connection?.invalidationHandler = nil
        connection = nil
    }

    func helper(errorHandler: @escaping @Sendable (Error) -> Void) -> HelperXPCProtocol? {
        guard
            let helper = currentConnection()?.remoteObjectProxyWithErrorHandler({ error in
                errorHandler(error)
            }) as? HelperXPCProtocol
        else { return nil }
        return helper
    }

    func checkIfLatestHelperIsInstalled() async -> Bool {
        Logger.helperClient.info(#function)

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/" + machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let bundledHelperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String
        else {
            Logger.helperClient.info("\(#function): false")
            return false
        }

        guard FileManager.default.fileExists(atPath: installedHelperURL.path) else {
            Logger.helperClient.info("\(#function): false")
            return false
        }

        do {
            let isInstalled = try await getVersion() == bundledHelperVersion
            Logger.helperClient.info("\(#function): \(String(describing: isInstalled), privacy: .public)")
            return isInstalled
        } catch {
            Logger.helperClient.error("\(#function): \(String(describing: error))")
            return false
        }
    }

    func getVersion() async throws -> String {
        Logger.helperClient.info(#function)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let box = ContinuationBox(continuation)
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                box.resume(throwing: HelperClientError.timedOut)
            }

            guard let helper = self.helper(errorHandler: {
                timeoutTask.cancel()
                box.resume(throwing: $0)
            }) else {
                timeoutTask.cancel()
                box.resume(throwing: HelperClientError.failedToCreateRemoteObjectProxy)
                return
            }
            helper.getVersion { version in
                timeoutTask.cancel()
                box.resume(returning: version)
            }
        }
    }

}

final class ContinuationBox<Output: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?

    init(_ continuation: CheckedContinuation<Output, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Output) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(throwing: error)
    }
}

enum HelperClientError: LocalizedError {
    case failedToCreateRemoteObjectProxy
    case timedOut
    case message(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreateRemoteObjectProxy:
            "Unable to communicate with privileged helper."
        case .timedOut:
            "Timed out communicating with privileged helper."
        case let .message(message):
            message
        }
    }
}
