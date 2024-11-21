import Foundation
import os.log

class XPCDelegate: NSObject, NSXPCListenerDelegate, HelperXPCProtocol {
    // MARK: - NSXPCListenerDelegate
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard ConnectionVerifier.isValid(connection: newConnection) else { return false }
        
        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
    
    // MARK: - HelperXPCProtocol
    
    func getVersion(completion: @escaping (String) -> Void) {
        Logger.xpcDelegate.info("\(#function)")
        completion(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
    }
    
    func xcodeSelect(absolutePath: String, completion: @escaping (Error?) -> Void) {
        Logger.xpcDelegate.info("\(#function)")

        guard URL(fileURLWithPath: absolutePath).hasDirectoryPath else {
            completion(XPCDelegateError(.invalidXcodePath))
            return
        }
        
        run(
            url: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-s", absolutePath],
            completion: completion
        )
    }

    func devToolsSecurityEnable(completion: @escaping (Error?) -> Void) {
        run(url: URL(fileURLWithPath: "/usr/sbin/DevToolsSecurity"), arguments: ["-enable"], completion: completion)
    }
    
    func addStaffToDevelopersGroup(completion: @escaping (Error?) -> Void) {
        run(url: URL(fileURLWithPath: "/usr/sbin/dseditgroup"), arguments: ["-o", "edit", "-t", "group", "-a", "staff", "_developer"], completion: completion)
    }
    
    func acceptXcodeLicense(absoluteXcodePath: String, completion: @escaping (Error?) -> Void) {
        run(url: URL(fileURLWithPath: absoluteXcodePath + "/Contents/Developer/usr/bin/xcodebuild"), arguments: ["-license", "accept"], completion: completion)
    }
    
    func runFirstLaunch(absoluteXcodePath: String, completion: @escaping (Error?) -> Void) {
        run(url: URL(fileURLWithPath: absoluteXcodePath + "/Contents/Developer/usr/bin/xcodebuild"), arguments: ["-runFirstLaunch"], completion: completion)
    }

    func moveApp(at source: String, to destination: String, completion: @escaping ((any Error)?) -> Void) {
        Logger.xpcDelegate.info("\(#function)")
        FileOperations.moveApp(at: source, to: destination, completion: completion)
    }

    func createSymbolicLink(source: String, destination: String, completion: @escaping ((any Error)?) -> Void) {
        Logger.xpcDelegate.info("\(#function)")
        FileOperations.createSymbolicLink(source: source, destination: destination, completion: completion)
    }

    func rename(source: String, destination: String, completion: @escaping ((any Error)?) -> Void) {
        Logger.xpcDelegate.info("\(#function)")
        FileOperations.rename(source: source, destination: destination, completion: completion)
    }

    func remove(path: String, completion: @escaping ((any Error)?) -> Void) {
        Logger.xpcDelegate.info("\(#function)")
        FileOperations.remove(path: path, completion: completion)
    }
}

// MARK: - Run

private func run(url: URL, arguments: [String], completion: @escaping (Error?) -> Void) {
    Logger.xpcDelegate.info("Run executable: \(url), arguments: \(arguments.joined(separator: ", "))")
    
    let process = Process()
    process.executableURL = url
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        completion(nil)
    } catch {
        completion(error)
    }
}
