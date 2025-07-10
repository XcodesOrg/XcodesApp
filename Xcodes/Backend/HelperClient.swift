import Combine
import Foundation
import os.log
import ServiceManagement

final class HelperClient {
    private var connection: NSXPCConnection?
    
    private func currentConnection() -> NSXPCConnection? {
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
    
    private func helper(errorSubject: PassthroughSubject<String, Error>) -> HelperXPCProtocol? {
        guard 
            let helper = self.currentConnection()?.remoteObjectProxyWithErrorHandler({ error in
                errorSubject.send(completion: .failure(error))
            }) as? HelperXPCProtocol 
        else { return nil }
        return helper
    }
    
    func checkIfLatestHelperIsInstalled() -> AnyPublisher<Bool, Never> {
        Logger.helperClient.info(#function)

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + machServiceName)
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
            .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0), privacy: .public)") })
            .eraseToAnyPublisher()
    }
    
    func getVersion() -> AnyPublisher<String, Error> {
        Logger.helperClient.info(#function)

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
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
                .map { _ in Void() }
        )
        .map { $0.0 }
        .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0), privacy: .public)") },
                      receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            Logger.helperClient.info("\(#function): finished") 
                        case let .failure(error):
                            Logger.helperClient.error("\(#function): \(String(describing: error))")
                        }
                      })
        .eraseToAnyPublisher()
    }
    
    func switchXcodePath(_ absolutePath: String) -> AnyPublisher<Void, Error> {
        Logger.helperClient.info("\(#function): \(absolutePath, privacy: .private(mask: .hash))")

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }
        
        return Deferred {
            Future { promise in
                helper.xcodeSelect(absolutePath: absolutePath, completion: { (possibleError) in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })                
            }
        }
        // Take values, but fail when connectionErrorSubject fails
        .zip(
            connectionErrorSubject
                .prepend("")
                .map { _ in Void() }
        )
        .map { $0.0 }
        .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
                      receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            Logger.helperClient.info("\(#function): finished") 
                        case let .failure(error):
                            Logger.helperClient.error("\(#function): \(String(describing: error))")
                        }
                      })
        .eraseToAnyPublisher()
    }
    
    func devToolsSecurityEnable() -> AnyPublisher<Void, Error> {
        Logger.helperClient.info(#function)

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }
        
        return Deferred {
            Future { promise in
                helper.devToolsSecurityEnable(completion: { (possibleError) in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })                
            }
        }
        // Take values, but fail when connectionErrorSubject fails
        .zip(
            connectionErrorSubject
                .prepend("")
                .map { _ in Void() }
        )
        .map { $0.0 }
        .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
                      receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            Logger.helperClient.info("\(#function): finished") 
                        case let .failure(error):
                            Logger.helperClient.error("\(#function): \(String(describing: error))")
                        }
                      })
        .eraseToAnyPublisher()
    }
    
    func addStaffToDevelopersGroup() -> AnyPublisher<Void, Error> {
        Logger.helperClient.info(#function)

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }
        
        return Deferred {
            Future { promise in
                helper.addStaffToDevelopersGroup(completion: { (possibleError) in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })                
            }
        }
        // Take values, but fail when connectionErrorSubject fails
        .zip(
            connectionErrorSubject
                .prepend("")
                .map { _ in Void() }
        )
        .map { $0.0 }
        .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
                      receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            Logger.helperClient.info("\(#function): finished") 
                        case let .failure(error):
                            Logger.helperClient.error("\(#function): \(String(describing: error))")
                        }
                      })
        .eraseToAnyPublisher()
    }
    
    func acceptXcodeLicense(absoluteXcodePath: String) -> AnyPublisher<Void, Error> {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }
        
        return Deferred {
            Future { promise in
                helper.acceptXcodeLicense(absoluteXcodePath: absoluteXcodePath, completion: { (possibleError) in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })                
            }
        }
        // Take values, but fail when connectionErrorSubject fails
        .zip(
            connectionErrorSubject
                .prepend("")
                .map { _ in Void() }
        )
        .map { $0.0 }
        .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
                      receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            Logger.helperClient.info("\(#function): finished") 
                        case let .failure(error):
                            Logger.helperClient.error("\(#function): \(String(describing: error))")
                        }
                      })
        .eraseToAnyPublisher()
    }
    
    func runFirstLaunch(absoluteXcodePath: String) -> AnyPublisher<Void, Error> {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }
        
        return Deferred {
            Future { promise in
                helper.runFirstLaunch(absoluteXcodePath: absoluteXcodePath, completion: { (possibleError) in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })                
            }
        }
        // Take values, but fail when connectionErrorSubject fails
        .zip(
            connectionErrorSubject
                .prepend("")
                .map { _ in Void() }
        )
        .map { $0.0 }
        .handleEvents(receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
                      receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            Logger.helperClient.info("\(#function): finished") 
                        case let .failure(error):
                            Logger.helperClient.error("\(#function): \(String(describing: error))")
                        }
                      })
        .eraseToAnyPublisher()
    }

    var usePrivilegedHelperForFileOperations: Bool {
        Current.defaults.bool(forKey: PreferenceKey.usePrivilegeHelperForFileOperations.rawValue) ?? false
    }

    func moveApp(at source:String, to destination: String) -> AnyPublisher<Void, Error> {
        if !usePrivilegedHelperForFileOperations {
            return Deferred {
                Future { promise in
                    FileOperations.moveApp(at: source, to: destination) { error in
                        if let error = error {
                            promise(.failure(error))
                        }
                        promise(.success(()))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.moveApp(at: source, to: destination) { error in
                    if let error = error {
                        promise(.failure(error))
                    }
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func createSymbolicLink(source: String, destination: String) -> AnyPublisher<Void, Error> {
        if !usePrivilegedHelperForFileOperations {
            return Deferred {
                Future { promise in
                    FileOperations.createSymbolicLink(source: source, destination: destination) { error in
                        if let error = error {
                            promise(.failure(error))
                        }
                        promise(.success(()))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        let connectionErrorSubject = PassthroughSubject<String, Error>()

        guard
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.createSymbolicLink(source: source, destination: destination) { error in
                    if let error = error {
                        promise(.failure(error))
                    }
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func rename(source: String, destination: String) -> AnyPublisher<Void, Error> {
        if !usePrivilegedHelperForFileOperations {
            return Deferred {
                Future { promise in
                    FileOperations.rename(source: source, destination: destination) { error in
                        if let error = error {
                            promise(.failure(error))
                        }
                        promise(.success(()))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        let connectionErrorSubject = PassthroughSubject<String, Error>()

        guard
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.rename(source: source, destination: destination) { error in
                    if let error = error {
                        promise(.failure(error))
                    }
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func remove(path: String) -> AnyPublisher<Void, Error> {
        if !usePrivilegedHelperForFileOperations {
            return Deferred {
                Future { promise in
                    FileOperations.remove(path: path) { error in
                        if let error = error {
                            promise(.failure(error))
                        }
                        promise(.success(()))
                    }
                }
            }
            .eraseToAnyPublisher()
        }

        let connectionErrorSubject = PassthroughSubject<String, Error>()

        guard
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))") })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.remove(path: path) { error in
                    if let error = error {
                        promise(.failure(error))
                    }
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
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
            if let error = cfError?.takeRetainedValue() { throw error }

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
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateRemoteObjectProxy:
            return localizeString("HelperClient.error")
        case let .message(message):
            return message
        }
    }
}
