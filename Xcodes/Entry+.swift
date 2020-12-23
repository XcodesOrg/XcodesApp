import Foundation
import Path

extension Entry {
    var isAppBundle: Bool {
        kind == .directory &&
        path.extension == "app" &&
        !path.isSymlink
    }

    var infoPlist: InfoPlist? {
        let infoPlistPath = path.join("Contents").join("Info.plist")
        guard
            let infoPlistData = try? Data(contentsOf: infoPlistPath.url),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData)
        else { return nil }

        return infoPlist
    }
}
