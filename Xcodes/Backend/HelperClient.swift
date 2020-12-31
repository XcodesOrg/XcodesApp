import Combine
import Foundation

final class HelperClient {
    private var connection: NSXPCConnection?
    
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
}
