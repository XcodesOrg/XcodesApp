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
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let bundledHelperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String
        else {
            return Just(false).eraseToAnyPublisher()
        }
        
        return getVersion()
            .map { installedHelperVersion in installedHelperVersion == bundledHelperVersion }
            .catch { _ in Just(false) }
            .eraseToAnyPublisher()
    }
    
    func getVersion() -> AnyPublisher<String, Error> {
        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: NSError())
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
        .eraseToAnyPublisher()
    }
    
    func switchXcodePath(_ absolutePath: String) -> AnyPublisher<Void, Error> {
        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: NSError())
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
        .eraseToAnyPublisher()
    }
    
    func devToolsSecurityEnable() -> AnyPublisher<Void, Error> {
        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: NSError())
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
        .eraseToAnyPublisher()
    }
    
    func addStaffToDevelopersGroup() -> AnyPublisher<Void, Error> {
        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: NSError())
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
        .eraseToAnyPublisher()
    }
    
    func acceptXcodeLicense(absoluteXcodePath: String) -> AnyPublisher<Void, Error> {
        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: NSError())
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
        .eraseToAnyPublisher()
    }
    
    func runFirstLaunch(absoluteXcodePath: String) -> AnyPublisher<Void, Error> {
        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard 
            let helper = self.helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: NSError())
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
        .eraseToAnyPublisher()
    }    
    
    // MARK: - Install
    // From https://github.com/securing/SimpleXPCApp/
    
    func install() {
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
        } catch {
            Logger.helperClient.error("\(error.localizedDescription)")
        }
    }
    
    private func executeAuthorizationFunction(_ authorizationFunction: () -> (OSStatus) ) throws {
        let osStatus = authorizationFunction()
        guard osStatus == errAuthorizationSuccess else {
            throw HelperClientError.message(String(describing: SecCopyErrorMessageString(osStatus, nil)))
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

enum HelperClientError: Error {
    case message(String)
}
