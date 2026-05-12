import Foundation

extension Bundle {
    var bundleName: String? {
        infoDictionary?["CFBundleName"] as? String
    }
    
    var shortVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var version: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }
    
    var humanReadableCopyright: String? {
        infoDictionary?["NSHumanReadableCopyright"] as? String
    }
}
