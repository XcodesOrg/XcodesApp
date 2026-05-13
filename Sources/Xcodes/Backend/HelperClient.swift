import Combine
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

final class HelperClient: @unchecked Sendable {
    var connection: NSXPCConnection?

    func currentConnection() -> NSXPCConnection? {
        guard self.connection == nil else {
            return self.connection
        }

        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.invalidationHandler = {
            self.connection?.invalidationHandler = nil
            DispatchQueue.main.async {
                self.connection = nil
            }
        }

        self.connection = connection
        connection.resume()

        return self.connection
    }

    func helper(errorSubject: PassthroughSubject<String, Error>) -> HelperXPCProtocol? {
        guard
            let helper = currentConnection()?.remoteObjectProxyWithErrorHandler({ error in
                errorSubject.send(completion: .failure(error))
            }) as? HelperXPCProtocol
        else { return nil }
        return helper
    }

    func checkIfLatestHelperIsInstalled() -> AnyPublisher<Bool, Never> {
        Logger.helperClient.info(#function)

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/" + machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let bundledHelperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String
        else {
            return Just(false)
                .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }

        return getVersion()
            .map { installedHelperVersion in installedHelperVersion == bundledHelperVersion }
            .catch { _ in Just(false) }
            // Failure is Never, so don't bother logging completion
            .handleEvents(receiveOutput: {
                Logger.helperClient.info("\(#function): \(String(describing: $0), privacy: .public)")
            })
            .eraseToAnyPublisher()
    }

    func getVersion() -> AnyPublisher<String, Error> {
        Logger.helperClient.info(#function)

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))")
                })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.getVersion { version in
                    promise(.success(version))
                }
            }
        }
        // Take values, but fail when connectionErrorSubject fails
        .zip(
            connectionErrorSubject
                .prepend("")
                .map { _ in () }
        )
        .map(\.0)
        .handleEvents(
            receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0), privacy: .public)") },
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Logger.helperClient.info("\(#function): finished")
                case let .failure(error):
                    Logger.helperClient.error("\(#function): \(String(describing: error))")
                }
            }
        )
        .eraseToAnyPublisher()
    }

}

enum HelperClientError: LocalizedError {
    case failedToCreateRemoteObjectProxy
    case message(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreateRemoteObjectProxy:
            "Unable to communicate with privileged helper."
        case let .message(message):
            message
        }
    }
}
