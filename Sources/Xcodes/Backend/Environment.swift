import AppleAPI
import Foundation
import Path
import Security
import XcodesKit

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct XcodesEnvironment: @unchecked Sendable {
    public var shell = Shell()
    public var files = Files()
    public var network = Network()
    public var keychain = Keychain()
    public var defaults = Defaults()
    public var date: () -> Date = Date.init
    public var helper = Helper()
    public var notificationManager = NotificationManager()
}

private final class CurrentEnvironmentStorage: @unchecked Sendable {
    static let shared = CurrentEnvironmentStorage()

    private let lock = NSRecursiveLock()
    private var environment = XcodesEnvironment()

    var value: XcodesEnvironment {
        get {
            lock.withLock { environment }
        }
        set {
            lock.withLock {
                environment = newValue
            }
        }
    }
}

public var current: XcodesEnvironment {
    get {
        CurrentEnvironmentStorage.shared.value
    }
    set {
        CurrentEnvironmentStorage.shared.value = newValue
    }
}

public struct Files: @unchecked Sendable {
    public var fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public func fileExists(atPath path: String) -> Bool {
        fileExistsAtPath(path)
    }

    public var moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }

    public var contentsAtPath: (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    public func contents(atPath path: String) -> Data? {
        contentsAtPath(path)
    }

    public var removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    public func removeItem(at URL: URL) throws {
        try removeItem(URL)
    }

    public var trashItem: (URL) throws -> URL = { try FileManager.default.trashItem(at: $0) }

    @discardableResult
    public func trashItem(at URL: URL) throws -> URL {
        try trashItem(URL)
    }

    public var createFile: (String, Data?, [FileAttributeKey: Any]?) -> Bool = { FileManager.default.createFile(
        atPath: $0,
        contents: $1,
        attributes: $2
    ) }

    @discardableResult
    public func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        createFile(path, data, attr)
    }

    public var createDirectory: (URL, Bool, [FileAttributeKey: Any]?) throws -> Void = FileManager.default
        .createDirectory(at:withIntermediateDirectories:attributes:)
    public func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try createDirectory(url, createIntermediates, attributes)
    }

    public var installedXcodes = _installedXcodes

    public func installedXcode(destination: Path) -> InstalledXcode? {
        if Path.isAppBundle(path: destination), Path.infoPlist(path: destination)?.bundleID == "com.apple.dt.Xcode" {
            InstalledXcode(path: destination)
        } else {
            nil
        }
    }

    public var write: (Data, URL) throws -> Void = { try $0.write(to: $1) }

    public func write(_ data: Data, to url: URL) throws {
        try write(data, url)
    }
}

private func _installedXcodes(destination: Path) -> [InstalledXcode] {
    destination.ls()
        .filter { $0.isAppBundle && $0.infoPlist?.bundleID == "com.apple.dt.Xcode" }
        .map { $0 }
        .compactMap(InstalledXcode.init)
}

public struct Network: @unchecked Sendable {
    private static let client = AppleAPI.Client()

    public var data: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await AppleAPI.current.network.session.data(for: request)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(request)
    }

    public var downloadTask: (URL, URL, Data?) -> (
        Progress,
        Task<(saveLocation: URL, response: URLResponse), Error>
    ) = { AppleAPI.current.network.session.downloadTaskAsync(with: $0, to: $1, resumingWith: $2) }

    public func downloadTask(
        with url: URL,
        to saveLocation: URL,
        resumingWith resumeData: Data?
    ) -> (progress: Progress, task: Task<
        (saveLocation: URL, response: URLResponse),
        Error
    >) {
        downloadTask(url, saveLocation, resumeData)
    }

    public var validateSession: @Sendable () async throws -> Void = {
        try await client.validateSession()
    }
}

public struct Keychain: @unchecked Sendable {
    private static let service = "eu.mpwg.xcodes"

    public var getString: (String) throws -> String? = { key in
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func getString(_ key: String) throws -> String? {
        try getString(key)
    }

    public var set: (String, String) throws -> Void = { value, key in
        let encodedValue = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: encodedValue
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = encodedValue

            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
    }

    public func set(_ value: String, key: String) throws {
        try set(value, key)
    }

    public var remove: (String) throws -> Void = { key in
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func remove(_ key: String) throws {
        try remove(key)
    }
}

public struct Defaults: @unchecked Sendable {
    public var string: (String) -> String? = { UserDefaults.standard.string(forKey: $0) }
    public func string(forKey key: String) -> String? {
        string(key)
    }

    public var date: (String) -> Date? = { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: $0)) }
    public func date(forKey key: String) -> Date? {
        date(key)
    }

    public var setDate: (Date?, String) -> Void = { UserDefaults.standard.set($0?.timeIntervalSince1970, forKey: $1) }
    public func setDate(_ value: Date?, forKey key: String) {
        setDate(value, key)
    }

    public var set: (Any?, String) -> Void = { UserDefaults.standard.set($0, forKey: $1) }
    public func set(_ value: Any?, forKey key: String) {
        set(value, key)
    }

    public var removeObject: (String) -> Void = { UserDefaults.standard.removeObject(forKey: $0) }
    public func removeObject(forKey key: String) {
        removeObject(key)
    }

    public var get: (String) -> Any? = { UserDefaults.standard.value(forKey: $0) }
    public func get(forKey key: String) -> Any? {
        get(key)
    }

    public var bool: (String) -> Bool? = { UserDefaults.standard.bool(forKey: $0) }
    public func bool(forKey key: String) -> Bool? {
        bool(key)
    }
}

private let helperClient = HelperClient()
public struct Helper: @unchecked Sendable {
    var install: () async throws -> Void = helperClient.install
    var checkIfLatestHelperIsInstalled: () async -> Bool = helperClient.checkIfLatestHelperIsInstalled
    var getVersion: () async throws -> String = helperClient.getVersion
    var switchXcodePath: (_ absolutePath: String) async throws -> Void = helperClient.switchXcodePath
    var devToolsSecurityEnable: () async throws -> Void = helperClient.devToolsSecurityEnable
    var addStaffToDevelopersGroup: () async throws -> Void = helperClient.addStaffToDevelopersGroup
    var acceptXcodeLicense: (_ absoluteXcodePath: String) async throws -> Void = helperClient.acceptXcodeLicense
    var runFirstLaunch: (_ absoluteXcodePath: String) async throws -> Void = helperClient.runFirstLaunch
}
