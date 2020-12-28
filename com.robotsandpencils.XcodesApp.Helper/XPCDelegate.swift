import Foundation

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
        NSLog("XPCDelegate: \(#function)")
        completion(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
    }
    
    func xcodeSelect(absolutePath: String, completion: @escaping (Error?) -> Void) {
        NSLog("XPCDelegate: \(#function)")

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
}

// MARK: - Run

private func run(url: URL, arguments: [String], completion: @escaping (Error?) -> Void) {
    NSLog("XPCDelegate: run \(url) \(arguments)")
    
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
