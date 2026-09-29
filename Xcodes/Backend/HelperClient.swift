import Foundation
import LegibleError
import os.log
import ServiceManagement
import XcodesKit

@MainActor
final class HelperClient {
    private var connection: NSXPCConnection?

    private func currentConnection() -> NSXPCConnection? {
        guard self.connection == nil else {
            return self.connection
        }

        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connection === connection else { return }
                connection.invalidationHandler = nil
                self.connection = nil
            }
        }

        self.connection = connection
        connection.resume()

        return self.connection
    }

    private func helper(errorHandler: @escaping @Sendable (Error) -> Void) -> HelperXPCProtocol? {
        guard
            let helper = self.currentConnection()?.remoteObjectProxyWithErrorHandler(errorHandler) as? HelperXPCProtocol
        else { return nil }
        return helper
    }

    func checkIfLatestHelperIsInstalledAsync() async throws -> Bool {
        Logger.helperClient.info(#function)

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let bundledHelperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String
        else {
            Logger.helperClient.info("\(#function): false")
            return false
        }

        let isInstalled = try await getVersionAsync() == bundledHelperVersion
        Logger.helperClient.info("\(#function): \(String(describing: isInstalled), privacy: .public)")
        return isInstalled
    }

    func getVersionAsync() async throws -> String {
        Logger.helperClient.info(#function)

        let version = try await performHelperRequest { helper, finish in
            helper.getVersion { version in
                finish(.success(version))
            }
        }
        Logger.helperClient.info("\(#function): \(String(describing: version), privacy: .public)")
        return version
    }

    func switchXcodePathAsync(_ absolutePath: String) async throws {
        Logger.helperClient.info("\(#function): \(absolutePath, privacy: .private(mask: .hash))")

        try await performVoidHelperRequest { helper, finish in
            helper.xcodeSelect(absolutePath: absolutePath) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func devToolsSecurityEnableAsync() async throws {
        Logger.helperClient.info(#function)

        try await performVoidHelperRequest { helper, finish in
            helper.devToolsSecurityEnable { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func addStaffToDevelopersGroupAsync() async throws {
        Logger.helperClient.info(#function)

        try await performVoidHelperRequest { helper, finish in
            helper.addStaffToDevelopersGroup { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func acceptXcodeLicenseAsync(absoluteXcodePath: String) async throws {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")

        try await performVoidHelperRequest { helper, finish in
            helper.acceptXcodeLicense(absoluteXcodePath: absoluteXcodePath) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func runFirstLaunchAsync(absoluteXcodePath: String) async throws {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")

        try await performVoidHelperRequest { helper, finish in
            helper.runFirstLaunch(absoluteXcodePath: absoluteXcodePath) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func moveAppAsync(at source: String, to destination: String) async throws {
        Logger.helperClient.info(#function)

        guard Current.helper.usePrivilegedHelperForFileOperations else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                FileOperations.moveApp(at: source, to: destination) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return
        }

        try await performVoidHelperRequest { helper, finish in
            helper.moveApp(at: source, to: destination) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func createSymbolicLinkAsync(source: String, destination: String) async throws {
        Logger.helperClient.info(#function)

        guard Current.helper.usePrivilegedHelperForFileOperations else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                FileOperations.createSymbolicLink(source: source, destination: destination) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return
        }

        try await performVoidHelperRequest { helper, finish in
            helper.createSymbolicLink(source: source, destination: destination) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func renameAsync(source: String, destination: String) async throws {
        Logger.helperClient.info(#function)

        guard Current.helper.usePrivilegedHelperForFileOperations else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                FileOperations.rename(source: source, destination: destination) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return
        }

        try await performVoidHelperRequest { helper, finish in
            helper.rename(source: source, destination: destination) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    func removeAsync(path: String) async throws {
        Logger.helperClient.info(#function)

        guard Current.helper.usePrivilegedHelperForFileOperations else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                FileOperations.remove(path: path) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return
        }

        try await performVoidHelperRequest { helper, finish in
            helper.remove(path: path) { possibleError in
                finish(possibleError.map(Result.failure) ?? .success(()))
            }
        }
        Logger.helperClient.info("\(#function): finished")
    }

    private func performVoidHelperRequest(_ operation: @escaping @Sendable (HelperXPCProtocol, @escaping @Sendable (Result<Void, Error>) -> Void) -> Void) async throws {
        try await performHelperRequest(operation)
    }

    private func performHelperRequest<T: Sendable>(_ operation: @escaping @Sendable (HelperXPCProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let request = OneShotContinuation<T>()
        guard let helper = helper(errorHandler: { error in
            request.resume(throwing: error)
        }) else {
            throw HelperClientError.failedToCreateRemoteObjectProxy
        }

        return try await request.value {
            operation(helper) { result in
                request.resume(with: result)
            }
        }
    }

    // MARK: - Install
    // From https://github.com/securing/SimpleXPCApp/

    func install() throws {
        Logger.helperClient.info(#function)

        var authItem = kSMRightBlessPrivilegedHelper.withCString { name in
            AuthorizationItem(name: name, valueLength: 0, value:UnsafeMutableRawPointer(bitPattern: 0), flags: 0)
        }
        var authRights = withUnsafeMutablePointer(to: &authItem) { authItem in
            AuthorizationRights(count: 1, items: authItem)
        }

        do {
            let authRef = try authorizationRef(&authRights, nil, [.interactionAllowed, .extendRights, .preAuthorize])
            var cfError: Unmanaged<CFError>?
            SMJobBless(kSMDomainSystemLaunchd, machServiceName as CFString, authRef, &cfError)
            if let error = cfError?.takeRetainedValue() {
                if CFErrorGetDomain(error) as String == kSMErrorDomainLaunchd as String,
                   CFErrorGetCode(error) == kSMErrorInvalidSignature {
                    throw HelperClientError.invalidSignature(underlyingError: error)
                }
                throw error
            }

            self.connection?.invalidate()
            self.connection = nil

            Logger.helperClient.info("\(#function): Finished installation")
        } catch {
            Logger.helperClient.error("\(#function): \(error.localizedDescription)")

            throw error
        }
    }

    private func executeAuthorizationFunction(_ authorizationFunction: () -> (OSStatus) ) throws {
        let osStatus = authorizationFunction()
        guard osStatus == errAuthorizationSuccess else {
            if let message = SecCopyErrorMessageString(osStatus, nil) {
                throw HelperClientError.message(String(message as NSString))
            } else {
                throw HelperClientError.message("Unknown error")
            }
        }
    }

    func authorizationRef(_ rights: UnsafePointer<AuthorizationRights>?,
                                 _ environment: UnsafePointer<AuthorizationEnvironment>?,
                                 _ flags: AuthorizationFlags) throws -> AuthorizationRef? {
        var authRef: AuthorizationRef?
        try executeAuthorizationFunction { AuthorizationCreate(rights, environment, flags, &authRef) }
        return authRef
    }
}

enum HelperClientError: LocalizedError {
    case failedToCreateRemoteObjectProxy
    case message(String)
    /// SMJobBless rejected the helper because its signature doesn't satisfy the app's SMPrivilegedExecutables requirement
    case invalidSignature(underlyingError: Error)
    /// The helper was blessed but doesn't answer, e.g. it rejects this app's signature via SMAuthorizedClients
    case unreachableAfterInstall(underlyingError: Error?)

    var errorDescription: String? {
        switch self {
        case .failedToCreateRemoteObjectProxy:
            return localizeString("HelperClient.error")
        case let .message(message):
            return message
        case let .invalidSignature(underlyingError):
            return Self.withDetails(localizeString("HelperClient.error.InvalidSignature"), underlyingError)
        case let .unreachableAfterInstall(underlyingError):
            return Self.withDetails(localizeString("HelperClient.error.UnreachableAfterInstall"), underlyingError)
        }
    }

    private static func withDetails(_ message: String, _ underlyingError: Error?) -> String {
        guard let underlyingError else { return message }
        return "\(message)\n\n\(underlyingError.legibleLocalizedDescription)"
    }
}
