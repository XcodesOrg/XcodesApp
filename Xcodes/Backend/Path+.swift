import Path
import Foundation
import XcodesKit

extension Path {
    static var defaultXcodesApplicationSupport: Path {
        XcodesPathResolver.appDefaultApplicationSupport
    }

    static var xcodesApplicationSupport: Path {
        XcodesPathResolver.appApplicationSupport(savedPath: Current.defaults.string(forKey: "localPath"))
    }
    
    static var cacheFile: Path {
        XcodesPathResolver.availableXcodesCacheFile(in: xcodesApplicationSupport)
    }
    
    static var defaultInstallDirectory: Path {
        XcodesPathResolver.appDefaultInstallDirectory
    }
    
    static var installDirectory: Path {
        XcodesPathResolver.appInstallDirectory(savedPath: Current.defaults.string(forKey: "installPath"))
    }
    
    static var runtimeCacheFile: Path {
        XcodesPathResolver.downloadableRuntimesCacheFile(in: xcodesApplicationSupport)
    }
    
    static var xcodesCaches: Path {
        XcodesPathResolver.appCaches()
    }
}
