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


// MARK: - Errors

struct XPCDelegateError: CustomNSError {    
    enum Code: Int {
        case invalidXcodePath
    }

    let code: Code
    
    init(_ code: Code) {
        self.code = code
    }
    
    // MARK: - CustomNSError
    
    static var errorDomain: String { "XPCDelegateError" }
    
    var errorCode: Int { code.rawValue }
    
    var errorUserInfo: [String : Any] {
        switch code {
        case .invalidXcodePath:
            return [
                NSLocalizedDescriptionKey: "Invalid Xcode path.",
                NSLocalizedFailureReasonErrorKey: "Xcode path must be absolute."
            ]
        }
    }
}
