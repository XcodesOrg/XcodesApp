import Foundation

let machServiceName = "com.robotsandpencils.XcodesApp.Helper"
let clientBundleID = "com.robotsandpencils.XcodesApp"
let subjectOrganizationalUnit = Bundle.main.infoDictionary!["CODE_SIGNING_SUBJECT_ORGANIZATIONAL_UNIT"] as! String

@objc(HelperXPCProtocol)
protocol HelperXPCProtocol {
    func getVersion(completion: @escaping (String) -> Void)
    func xcodeSelect(absolutePath: String, completion: @escaping (Error?) -> Void)
    func devToolsSecurityEnable(completion: @escaping (Error?) -> Void)
    func addStaffToDevelopersGroup(completion: @escaping (Error?) -> Void)
    func acceptXcodeLicense(absoluteXcodePath: String, completion: @escaping (Error?) -> Void)
    func runFirstLaunch(absoluteXcodePath: String, completion: @escaping (Error?) -> Void)
}
