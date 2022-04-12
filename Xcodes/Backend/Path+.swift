import Path
import Foundation

extension Path {
    static let defaultXcodesApplicationSupport = Path.applicationSupport/"com.robotsandpencils.XcodesApp"
    static var xcodesApplicationSupport: Path {
        guard let savedApplicationSupport = Current.defaults.string(forKey: "localPath") else {
            return defaultXcodesApplicationSupport
        }
        guard let path = Path(savedApplicationSupport) else {
            return defaultXcodesApplicationSupport
        }
        return path
    }
    
    static var cacheFile: Path {
        return xcodesApplicationSupport/"available-xcodes.json"
    }
    
    static var installDirectory: Path {
        return Path.root/"Applications"
    }
}
