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
    
    static let defaultInstallDirectory = Path.root/"Applications"
    
    static var installDirectory: Path {
        guard let savedInstallDirectory = Current.defaults.string(forKey: "installPath") else {
            return defaultInstallDirectory
        }
        guard let path = Path(savedInstallDirectory) else {
            return defaultInstallDirectory
        }
        return path
    }
    
    static var runtimeCacheFile: Path {
        return xcodesApplicationSupport/"downloadable-runtimes.json"
    }
}
