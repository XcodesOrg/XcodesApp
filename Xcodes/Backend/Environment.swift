import Foundation
import PromiseKit
import PMKFoundation
import Path
import AppleAPI
import KeychainAccess

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment {
    public var shell = Shell()
    public var files = Files()
    public var network = Network()
    public var logging = Logging()
    public var keychain = Keychain()
    public var defaults = Defaults()
}

public var Current = Environment()

public struct Shell {
    public var unxip: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.xip, workingDirectory: $0.deletingLastPathComponent(), "--expand", "\($0.path)") }
    public var spctlAssess: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.spctl, "--assess", "--verbose", "--type", "execute", "\($0.path)") }
    public var codesignVerify: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.codesign, "-vv", "-d", "\($0.path)") }
    public var devToolsSecurityEnable: (String?) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.sbin.DevToolsSecurity, "-enable") }
    public var addStaffToDevelopersGroup: (String?) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.sbin.dseditgroup, "-o", "edit", "-t", "group", "-a", "staff", "_developer") }
    public var acceptXcodeLicense: (InstalledXcode, String?) -> Promise<ProcessOutput> = { Process.sudo(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"), "-license", "accept") }
    public var runFirstLaunch: (InstalledXcode, String?) -> Promise<ProcessOutput> = { Process.sudo(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"),"-runFirstLaunch") }
    public var buildVersion: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sw_vers, "-buildVersion") }
    public var xcodeBuildVersion: (InstalledXcode) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.libexec.PlistBuddy, "-c", "Print :ProductBuildVersion", "\($0.path.string)/Contents/version.plist") }
    public var getUserCacheDir: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.getconf, "DARWIN_USER_CACHE_DIR") }
    public var touchInstallCheck: (String, String, String) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin/"touch", "\($0)com.apple.dt.Xcode.InstallCheckCache_\($1)_\($2)") }

    public var validateSudoAuthentication: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, "-nv") }
    public var authenticateSudoerIfNecessary: (@escaping () -> Promise<String>) -> Promise<String?> = { passwordInput in
        firstly { () -> Promise<String?> in
            Current.shell.validateSudoAuthentication().map { _ in return nil }
        }
        .recover { _ -> Promise<String?> in
            return passwordInput().map(Optional.init)
        }
    }
    public func authenticateSudoerIfNecessary(passwordInput: @escaping () -> Promise<String>) -> Promise<String?> {
        authenticateSudoerIfNecessary(passwordInput)
    }

    public var xcodeSelectPrintPath: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.join("xcode-select"), "-p") }
    public var xcodeSelectSwitch: (String?, String) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.bin.join("xcode-select"), "-s", $1) }
    public func xcodeSelectSwitch(password: String?, path: String) -> Promise<ProcessOutput> {
        xcodeSelectSwitch(password, path)
    }
}

public struct Files {
    public var fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public func fileExists(atPath path: String) -> Bool {
        return fileExistsAtPath(path)
    }

    public var moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }

    public var contentsAtPath: (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    public func contents(atPath path: String) -> Data? {
        return contentsAtPath(path)
    }

    public var removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    public func removeItem(at URL: URL) throws {
        try removeItem(URL)
    }

    public var trashItem: (URL) throws -> URL = { try FileManager.default.trashItem(at: $0) }

    @discardableResult
    public func trashItem(at URL: URL) throws -> URL {
        return try trashItem(URL)
    }
    
    public var createFile: (String, Data?, [FileAttributeKey: Any]?) -> Bool = { FileManager.default.createFile(atPath: $0, contents: $1, attributes: $2) }
    
    @discardableResult
    public func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        return createFile(path, data, attr)
    }

    public var createDirectory: (URL, Bool, [FileAttributeKey : Any]?) throws -> Void = FileManager.default.createDirectory(at:withIntermediateDirectories:attributes:)
    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        try createDirectory(url, createIntermediates, attributes)
    }

    public var installedXcodes = _installedXcodes
}
private func _installedXcodes(destination: Path) -> [InstalledXcode] {
    ((try? destination.ls()) ?? [])
        .filter { $0.isAppBundle && $0.infoPlist?.bundleID == "com.apple.dt.Xcode" }
        .map { $0.path }
        .compactMap(InstalledXcode.init)
}

public struct Network {
    private static let client = AppleAPI.Client()

    public var dataTask: (URLRequestConvertible) -> Promise<(data: Data, response: URLResponse)> = { AppleAPI.Current.network.session.dataTask(.promise, with: $0) }
    public func dataTask(with convertible: URLRequestConvertible) -> Promise<(data: Data, response: URLResponse)> {
        dataTask(convertible)
    }

    public var downloadTask: (URLRequestConvertible, URL, Data?) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) = { AppleAPI.Current.network.session.downloadTask(with: $0, to: $1, resumingWith: $2) }

    public func downloadTask(with convertible: URLRequestConvertible, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        return downloadTask(convertible, saveLocation, resumeData)
    }
}

public struct Logging {
    public var log: (String) -> Void = { print($0) }
}

public struct Keychain {
    private static let keychain = KeychainAccess.Keychain(service: "com.robotsandpencils.XcodesApp")

    public var getString: (String) throws -> String? = keychain.getString(_:)
    public func getString(_ key: String) throws -> String? {
        try getString(key)
    }

    public var set: (String, String) throws -> Void = keychain.set(_:key:)
    public func set(_ value: String, key: String) throws {
        try set(value, key)
    }

    public var remove: (String) throws -> Void = keychain.remove(_:)
    public func remove(_ key: String) throws -> Void {
        try remove(key)
    }
}

public struct Defaults {
    public var string: (String) -> String? = { UserDefaults.standard.string(forKey: $0) }
    public func string(forKey key: String) -> String? {
        string(key)
    }
    
    public var set: (Any?, String) -> Void = { UserDefaults.standard.set($0, forKey: $1) }
    public func set(_ value: Any?, forKey key: String) {
        set(value, key)
    }
    
    public var removeObject: (String) -> Void = { UserDefaults.standard.removeObject(forKey: $0) }
    public func removeObject(forKey key: String) {
        removeObject(key)
    }
}
