import Foundation
@preconcurrency import Path

public struct XcodesPathResolver: Sendable {
    public static let appDefaultApplicationSupport = Path.applicationSupport/"com.robotsandpencils.XcodesApp"
    public static let appDefaultInstallDirectory = Path.root/"Applications"

    public static func appApplicationSupport(savedPath: String?) -> Path {
        path(from: savedPath) ?? appDefaultApplicationSupport
    }

    public static func appInstallDirectory(savedPath: String?) -> Path {
        path(from: savedPath) ?? appDefaultInstallDirectory
    }

    public static func appCaches() -> Path {
        Path.caches/"com.xcodesorg.xcodesapp"
    }

    public static func availableXcodesCacheFile(in applicationSupport: Path) -> Path {
        applicationSupport/"available-xcodes.json"
    }

    public static func downloadableRuntimesCacheFile(in applicationSupport: Path) -> Path {
        applicationSupport/"downloadable-runtimes.json"
    }

    public static func cliHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> Path {
        environment["HOME"].flatMap(Path.init) ?? Path(.home)
    }

    public static func cliApplicationSupport(home: Path) -> Path {
        home/"Library/Application Support/com.robotsandpencils.xcodes"
    }

    public static func cliOldApplicationSupport(home: Path) -> Path {
        home/"Library/Application Support/ca.brandonevans.xcodes"
    }

    public static func cliCaches(home: Path) -> Path {
        home/"Library/Caches/com.robotsandpencils.xcodes"
    }

    public static func cliDownloads(home: Path) -> Path {
        home/"Downloads"
    }

    public static func cliAvailableXcodesCacheFile(applicationSupport: Path) -> Path {
        availableXcodesCacheFile(in: applicationSupport)
    }

    public static func cliConfigurationFile(applicationSupport: Path) -> Path {
        applicationSupport/"configuration.json"
    }

    private static func path(from savedPath: String?) -> Path? {
        savedPath.flatMap(Path.init)
    }
}
