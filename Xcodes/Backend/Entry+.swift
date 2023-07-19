import Foundation
import Path

extension Entry {
    static func isAppBundle(kind: Kind, path: Path) -> Bool {
        kind == .directory &&
        path.extension == "app" &&
        !path.isSymlink
    }
    static func infoPlist(kind: Kind, path: Path) -> InfoPlist? {
        let infoPlistPath = path.join("Contents").join("Info.plist")
        guard
            let infoPlistData = try? Data(contentsOf: infoPlistPath.url),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData)
        else { return nil }

        return infoPlist
    }
    
    var isAppBundle: Bool {
        Entry.isAppBundle(kind: kind, path: path)
    }

    var infoPlist: InfoPlist? {
        Entry.infoPlist(kind: kind, path: path)
    }
}
