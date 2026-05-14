import Foundation
import Path

extension Path {
    static let defaultRhodonlicationSupport = Path.applicationSupport / "eu.mpwg.rhodon"
    static var rhodonApplicationSupport: Path {
        guard let savedApplicationSupport = current.defaults.string(forKey: "localPath") else {
            return defaultRhodonlicationSupport
        }
        guard let path = Path(savedApplicationSupport) else {
            return defaultRhodonlicationSupport
        }
        return path
    }

    static var cacheFile: Path {
        rhodonApplicationSupport / "available-rhodon.json"
    }

    static let defaultInstallDirectory = Path.root / "Applications"

    static var installDirectory: Path {
        guard let savedInstallDirectory = current.defaults.string(forKey: "installPath") else {
            return defaultInstallDirectory
        }
        guard let path = Path(savedInstallDirectory) else {
            return defaultInstallDirectory
        }
        return path
    }

    static var runtimeCacheFile: Path {
        rhodonApplicationSupport / "downloadable-runtimes.json"
    }

    static var rhodonCaches: Path {
        caches / "eu.mpwg.rhodon"
    }

    @discardableResult
    func setCurrentUserAsOwner() -> Path {
        let user = ProcessInfo.processInfo.environment["SUDO_USER"] ?? NSUserName()
        try? FileManager.default.setAttributes([.ownerAccountName: user], ofItemAtPath: string)
        return self
    }
}
