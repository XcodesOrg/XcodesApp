import Foundation

let machServiceName = "com.xcodesorg.xcodesapp.Helper"
let clientBundleID = "com.xcodesorg.xcodesapp"
let subjectOrganizationalUnit = Bundle.main.infoDictionary!["CODE_SIGNING_SUBJECT_ORGANIZATIONAL_UNIT"] as! String

@objc(HelperXPCProtocol)
protocol HelperXPCProtocol {
    func getVersion(completion: @escaping (String) -> Void)
    func xcodeSelect(absolutePath: String, completion: @escaping (Error?) -> Void)
    func devToolsSecurityEnable(completion: @escaping (Error?) -> Void)
    func addStaffToDevelopersGroup(completion: @escaping (Error?) -> Void)
    func acceptXcodeLicense(absoluteXcodePath: String, completion: @escaping (Error?) -> Void)
    func runFirstLaunch(absoluteXcodePath: String, completion: @escaping (Error?) -> Void)
    func moveApp(at source: String, to destination: String, completion: @escaping (Error?) -> Void)
    func createSymbolicLink(source: String, destination: String, completion: @escaping (Error?) -> Void)
    func rename(source: String, destination: String, completion: @escaping (Error?) -> Void)
    func remove(path: String, completion: @escaping (Error?) -> Void)
}

struct XPCDelegateError: CustomNSError {
    enum Code: Int {
        case invalidXcodePath
        case invalidSourcePath
        case invalidDestinationPath
        case destinationIsNotASymbolicLink
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
        case .invalidSourcePath:
            return [
                NSLocalizedDescriptionKey: "Invalid source path.",
                NSLocalizedFailureReasonErrorKey: "Source path must be absolute and must be a directory."
            ]
        case .invalidDestinationPath:
            return [
                NSLocalizedDescriptionKey: "Invalid destination path.",
                NSLocalizedFailureReasonErrorKey: "Destination path must be absolute and must be a directory."
            ]
        case .destinationIsNotASymbolicLink:
            return [
                NSLocalizedDescriptionKey: "Invalid destination path.",
                NSLocalizedFailureReasonErrorKey: "Destination path must be a symbolic link."
            ]
        }
    }
}
