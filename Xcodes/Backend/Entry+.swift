import Foundation
import Path

extension Path {
    static func isAppBundle(path: Path) -> Bool {
        path.isDirectory &&
        path.extension == "app" &&
        !path.isSymlink
    }
    static func infoPlist(path: Path) -> InfoPlist? {
        let infoPlistPath = path.join("Contents").join("Info.plist")
        guard
            let infoPlistData = try? Data(contentsOf: infoPlistPath.url),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData)
        else { return nil }

        return infoPlist
    }
    
    var isAppBundle: Bool {
        Path.isAppBundle(path: self)
    }

    var infoPlist: InfoPlist? {
        Path.infoPlist(path: self)
    }
}
