import Foundation
import Path
import KeychainAccess
import XcodesKit
import XcodesLoginKit
import os
/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment: Sendable {
    public var shell = Shell()
    public var files = Files()
    public var network = Network()
    public var keychain = Keychain()
    public var defaults = Defaults()
    public var date: @Sendable () -> Date = { Date() }
    public var helper = Helper()
    public var notificationManager = NotificationManager()
}

private let currentEnvironment = CurrentEnvironmentStorage(Environment())

public var Current: Environment {
    get { currentEnvironment.value }
    set { currentEnvironment.value = newValue }
}

private final class CurrentEnvironmentStorage: Sendable {
    private let environment: OSAllocatedUnfairLock<Environment>

    var value: Environment {
        get { environment.withLock { $0 } }
        set { environment.withLock { $0 = newValue } }
    }

    init(_ environment: Environment) {
        self.environment = OSAllocatedUnfairLock(initialState: environment)
    }
}

public struct Shell: Sendable {
    private static let shared = XcodesShell()

    public var unxip = Shell.shared.unxip
    public var spctlAssess = Shell.shared.spctlAssess
    public var codesignVerify = Shell.shared.codesignVerify
    public var buildVersion = Shell.shared.buildVersion
    public var xcodeBuildVersion = Shell.shared.xcodeBuildVersion
    public var archs = Shell.shared.archs
    public var getUserCacheDir = Shell.shared.getUserCacheDir
    public var touchInstallCheck = Shell.shared.touchInstallCheck

    public var xcodeSelectPrintPath = Shell.shared.xcodeSelectPrintPath
    
    public var downloadWithAria2Async: @Sendable (Path, URL, Path, [HTTPCookie]) -> AsyncThrowingStream<Progress, Error> = { aria2Path, url, destination, cookies in
        Aria2DownloadService().download(aria2Path: aria2Path, url: url, destination: destination, cookies: cookies)
    }
    
    
    public var unxipExperiment: @Sendable (URL) async throws -> ProcessOutput = { url in
        let unxipPath = Path(url: Bundle.main.url(forAuxiliaryExecutable: "unxip")!)!
        return try await Process.runAsync(unxipPath.url, workingDirectory: url.deletingLastPathComponent(), ["\(url.path)"])
    }
    
    public var downloadRuntime: @Sendable (String, String, String?) -> AsyncThrowingStream<Progress, Error> = { platform, version, architecture in
        XcodebuildRuntimeDownloadService().download(platform: platform, buildVersion: version, architecture: architecture)
    }
}

public struct Files: Sendable {
    public var fileExistsAtPath: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public func fileExists(atPath path: String) -> Bool {
        return fileExistsAtPath(path)
    }

    public var moveItem: @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }

    public var contentsAtPath: @Sendable (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    public func contents(atPath path: String) -> Data? {
        return contentsAtPath(path)
    }

    public var removeItem: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    public func removeItem(at URL: URL) throws {
        try removeItem(URL)
    }

    public var trashItem: @Sendable (URL) throws -> URL = { try FileManager.default.trashItem(at: $0) }

    @discardableResult
    public func trashItem(at URL: URL) throws -> URL {
        return try trashItem(URL)
    }
    
    public var createFile: @Sendable (String, Data?, [FileAttributeKey: Any]?) -> Bool = { FileManager.default.createFile(atPath: $0, contents: $1, attributes: $2) }
    
    @discardableResult
    public func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        return createFile(path, data, attr)
    }

    public var createDirectory: @Sendable (URL, Bool, [FileAttributeKey : Any]?) throws -> Void = { url, createIntermediates, attributes in
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        try createDirectory(url, createIntermediates, attributes)
    }

    public var installedXcodes: @Sendable (Path) -> [InstalledXcode] = { destination in
        _installedXcodes(destination: destination)
    }
    
    public func installedXcode(destination: Path) -> InstalledXcode? {
        InstalledXcodeDiscoveryService(
            listDirectory: { _ in [] },
            contentsAtPath: contentsAtPath,
            loadArchitectures: Current.shell.archs
        ).installedXcode(at: destination)
    }
    
    public var write: @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }

    public func write(_ data: Data, to url: URL) throws {
        try write(data, url)
    }
}

private func _installedXcodes(destination: Path) -> [InstalledXcode] {
    InstalledXcodeDiscoveryService(
        listDirectory: { $0.ls() },
        contentsAtPath: { path in FileManager.default.contents(atPath: path) },
        loadArchitectures: Current.shell.archs
    ).installedXcodes(in: destination)
}

public struct Network: Sendable {
    public private(set) var loginClient: XcodesLoginKit.Client

    public var session: URLSession {
        get { loginClient.urlSession }
        set {
            let loginClient = XcodesLoginKit.Client(urlSession: newValue)
            self.loginClient = loginClient
            configureDefaultOperations(using: loginClient)
        }
    }

    public var loadData: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public func dataTaskAsync(with request: URLRequest) async throws -> (Data, URLResponse) {
        try await loadData(request)
    }
    
    public var downloadTaskAsync: @Sendable (URL, URL, Data?) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>)

    public func downloadTaskAsync(with url: URL, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, task: Task<(saveLocation: URL, response: URLResponse), Error>) {
        downloadTaskAsync(url, saveLocation, resumeData)
    }
    
    public var validateSessionAsync: @Sendable () async throws -> Void

    public var signout: @Sendable () -> Void

    public init(
        session: URLSession? = nil,
        loadData: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
        downloadTaskAsync: (@Sendable (URL, URL, Data?) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>))? = nil,
        validateSessionAsync: (@Sendable () async throws -> Void)? = nil,
        signout: (@Sendable () -> Void)? = nil
    ) {
        let loginClient: XcodesLoginKit.Client
        if let session {
            loginClient = XcodesLoginKit.Client(urlSession: session)
        } else {
            loginClient = XcodesLoginKit.Client()
        }
        self.loginClient = loginClient
        self.loadData = loadData ?? { request in
            try await loginClient.urlSession.data(for: request)
        }
        self.downloadTaskAsync = downloadTaskAsync ?? { url, saveLocation, resumeData in
            loginClient.urlSession.downloadTaskAsync(with: url, to: saveLocation, resumingWith: resumeData)
        }
        self.validateSessionAsync = validateSessionAsync ?? {
            _ = try await loginClient.validateSession()
        }
        self.signout = signout ?? {
            loginClient.signout()
        }
    }

    private mutating func configureDefaultOperations(using loginClient: XcodesLoginKit.Client) {
        self.loadData = { request in
            try await loginClient.urlSession.data(for: request)
        }
        self.downloadTaskAsync = { url, saveLocation, resumeData in
            loginClient.urlSession.downloadTaskAsync(with: url, to: saveLocation, resumingWith: resumeData)
        }
        self.validateSessionAsync = {
            _ = try await loginClient.validateSession()
        }
        self.signout = {
            loginClient.signout()
        }
    }
}

public struct Keychain: Sendable {
    private static var keychain: KeychainAccess.Keychain {
        KeychainAccess.Keychain(service: "com.robotsandpencils.XcodesApp")
    }

    public var getString: @Sendable (String) throws -> String? = { try keychain.getString($0) }
    public func getString(_ key: String) throws -> String? {
        try getString(key)
    }

    public var set: @Sendable (String, String) throws -> Void = { try keychain.set($0, key: $1) }
    public func set(_ value: String, key: String) throws {
        try set(value, key)
    }

    public var remove: @Sendable (String) throws -> Void = { try keychain.remove($0) }
    public func remove(_ key: String) throws -> Void {
        try remove(key)
    }
}

public struct Defaults: Sendable {
    public var string: @Sendable (String) -> String? = { UserDefaults.standard.string(forKey: $0) }
    public func string(forKey key: String) -> String? {
        string(key)
    }
    
    public var date: @Sendable (String) -> Date? = { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: $0)) }
    public func date(forKey key: String) -> Date? {
        date(key)
    }
    
    public var setDate: @Sendable (Date?, String) -> Void = { UserDefaults.standard.set($0?.timeIntervalSince1970, forKey: $1) }
    public func setDate(_ value: Date?, forKey key: String) {
        setDate(value, key)
    }
    
    public var set: @Sendable (Any?, String) -> Void = { UserDefaults.standard.set($0, forKey: $1) }
    public func set(_ value: Any?, forKey key: String) {
        set(value, key)
    }
    
    public var removeObject: @Sendable (String) -> Void = { UserDefaults.standard.removeObject(forKey: $0) }
    public func removeObject(forKey key: String) {
        removeObject(key)
    }
    
    public var get: @Sendable (String) -> Any? = { UserDefaults.standard.value(forKey: $0) }
    public func get(forKey key: String) -> Any? {
        get(key)
    }
    
    public var bool: @Sendable (String) -> Bool? = { UserDefaults.standard.bool(forKey: $0) }
    public func bool(forKey key: String) -> Bool? {
        bool(key)
    }
}

@MainActor
private let helperClient = HelperClient()
public struct Helper: Sendable {
    var install: @Sendable () async throws -> Void = { try await helperClient.install() }
    var checkIfLatestHelperIsInstalledAsync: @Sendable () async throws -> Bool = { try await helperClient.checkIfLatestHelperIsInstalledAsync() }
    var getVersionAsync: @Sendable () async throws -> String = { try await helperClient.getVersionAsync() }
    var switchXcodePathAsync: @Sendable (_ absolutePath: String) async throws -> Void = { try await helperClient.switchXcodePathAsync($0) }
    var devToolsSecurityEnableAsync: @Sendable () async throws -> Void = { try await helperClient.devToolsSecurityEnableAsync() }
    var addStaffToDevelopersGroupAsync: @Sendable () async throws -> Void = { try await helperClient.addStaffToDevelopersGroupAsync() }
    var acceptXcodeLicenseAsync: @Sendable (_ absoluteXcodePath: String) async throws -> Void = { try await helperClient.acceptXcodeLicenseAsync(absoluteXcodePath: $0) }
    var runFirstLaunchAsync: @Sendable (_ absoluteXcodePath: String) async throws -> Void = { try await helperClient.runFirstLaunchAsync(absoluteXcodePath: $0) }
}
