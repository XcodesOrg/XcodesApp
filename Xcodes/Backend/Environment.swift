import Combine
import Foundation
import Path
import AppleAPI
import KeychainAccess
import XcodesKit
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
    public var keychain = Keychain()
    public var defaults = Defaults()
    public var date: () -> Date = Date.init
    public var helper = Helper()
    public var notificationManager = NotificationManager()
}

public var Current = Environment()

public struct Shell {
    public var unxip: (URL) -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.bin.xip, workingDirectory: $0.deletingLastPathComponent(), "--expand", "\($0.path)") }
    public var spctlAssess: (URL) -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.sbin.spctl, "--assess", "--verbose", "--type", "execute", "\($0.path)") }
    public var codesignVerify: (URL) -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.bin.codesign, "-vv", "-d", "\($0.path)") }
    public var buildVersion: () -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.bin.sw_vers, "-buildVersion") }
    public var xcodeBuildVersion: (InstalledXcode) -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.libexec.PlistBuddy, "-c", "Print :ProductBuildVersion", "\($0.path.string)/Contents/version.plist") }
    public var getUserCacheDir: () -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.bin.getconf, "DARWIN_USER_CACHE_DIR") }
    public var touchInstallCheck: (String, String, String) -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.bin/"touch", "\($0)com.apple.dt.Xcode.InstallCheckCache_\($1)_\($2)") }

    public var xcodeSelectPrintPath: () -> AnyPublisher<ProcessOutput, Error> = { Process.run(Path.root.usr.bin.join("xcode-select"), "-p") }
    
    public var downloadWithAria2: (Path, URL, Path, [HTTPCookie]) -> (Progress, AnyPublisher<Void, Error>) = { aria2Path, url, destination, cookies in
        let process = Process()
        process.executableURL = aria2Path.url
        process.arguments = [
            "--header=Cookie: \(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))",     
            "--max-connection-per-server=16",
            "--split=16",
            "--summary-interval=1",
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)", // if xcodes quits, stop aria2 process
            "--dir=\(destination.parent.string)",
            "--out=\(destination.basename())",
            "--human-readable=false", // sets the output to use bytes instead of formatting
            url.absoluteString,
        ]
        let stdOutPipe = Pipe()
        process.standardOutput = stdOutPipe
        let stdErrPipe = Pipe()
        process.standardError = stdErrPipe
        
        var progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = .downloading
        
        let observer = NotificationCenter.default.addObserver(
            forName: .NSFileHandleDataAvailable, 
            object: nil, 
            queue: OperationQueue.main
        ) { note in
            guard
                // This should always be the case for Notification.Name.NSFileHandleDataAvailable
                let handle = note.object as? FileHandle,
                handle === stdOutPipe.fileHandleForReading || handle === stdErrPipe.fileHandleForReading
            else { return }

            defer { handle.waitForDataInBackgroundAndNotify() }

            let string = String(decoding: handle.availableData, as: UTF8.self)
            
            progress.updateFromAria2(string: string)
        }

        stdOutPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        stdErrPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        
        do {
            try process.run()
        } catch {
            return (progress, Fail(error: error).eraseToAnyPublisher())
        }

        let publisher = Deferred {
            Future<Void, Error> { promise in
                DispatchQueue.global(qos: .default).async {
                    process.waitUntilExit()
                    
                    NotificationCenter.default.removeObserver(observer, name: .NSFileHandleDataAvailable, object: nil)
                    
                    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                        if let aria2cError = Aria2CError(exitStatus: process.terminationStatus) {
                            return promise(.failure(aria2cError))
                        } else {
                            return promise(.failure(ProcessExecutionError(process: process, standardOutput: "", standardError: "")))
                        }
                    }
                    promise(.success(()))
                }
            }
        }
        .handleEvents(receiveCancel: {
            process.terminate()
            NotificationCenter.default.removeObserver(observer, name: .NSFileHandleDataAvailable, object: nil)
        })
        .eraseToAnyPublisher()
        
        return (progress, publisher)
    }
    
    public var downloadWithAria2Async: (Path, URL, Path, [HTTPCookie]) -> AsyncThrowingStream<Progress, Error> = { aria2Path, url, destination, cookies in
        return AsyncThrowingStream<Progress, Error> { continuation in
 
            Task {
                // Assume progress will not have data races, so we manually opt-out isolation checks.
                nonisolated(unsafe) var progress = Progress()
                progress.kind = .file
                progress.fileOperationKind = .downloading
                
                let process = Process()
                process.executableURL = aria2Path.url
                process.arguments = [
                    "--header=Cookie: \(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))",
                    "--max-connection-per-server=16",
                    "--split=16",
                    "--summary-interval=1",
                    "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)", // if xcodes quits, stop aria2 process
                    "--dir=\(destination.parent.string)",
                    "--out=\(destination.basename())",
                    "--human-readable=false", // sets the output to use bytes instead of formatting
                    url.absoluteString,
                ]
                let stdOutPipe = Pipe()
                process.standardOutput = stdOutPipe
                let stdErrPipe = Pipe()
                process.standardError = stdErrPipe
                
                let observer = NotificationCenter.default.addObserver(
                    forName: .NSFileHandleDataAvailable,
                    object: nil,
                    queue: OperationQueue.main
                ) { note in
                    guard
                        // This should always be the case for Notification.Name.NSFileHandleDataAvailable
                        let handle = note.object as? FileHandle,
                        handle === stdOutPipe.fileHandleForReading || handle === stdErrPipe.fileHandleForReading
                    else { return }
                    
                    defer { handle.waitForDataInBackgroundAndNotify() }
                    
                    let string = String(decoding: handle.availableData, as: UTF8.self)
                    // TODO: fix warning. ObservingProgressView is currently tied to an updating progress
                    progress.updateFromAria2(string: string)
                    
                    continuation.yield(progress)
                }
                
                stdOutPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
                stdErrPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
                
                continuation.onTermination = { @Sendable _ in
                    process.terminate()
                    NotificationCenter.default.removeObserver(observer, name: .NSFileHandleDataAvailable, object: nil)
                }
                
                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                }
                
                process.waitUntilExit()
                
                NotificationCenter.default.removeObserver(observer, name: .NSFileHandleDataAvailable, object: nil)
                
                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    if let aria2cError = Aria2CError(exitStatus: process.terminationStatus) {
                        continuation.finish(throwing: aria2cError)
                    } else {
                        continuation.finish(throwing: ProcessExecutionError(process: process, standardOutput: "", standardError: ""))
                    }
                    return
                }
                continuation.finish()
            }
        }
    }
    
    
    public var unxipExperiment: (URL) -> AnyPublisher<ProcessOutput, Error> = { url in
        let unxipPath = Path(url: Bundle.main.url(forAuxiliaryExecutable: "unxip")!)!
        return Process.run(unxipPath.url, workingDirectory: url.deletingLastPathComponent(), ["\(url.path)"])
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
    
    public func installedXcode(destination: Path) -> InstalledXcode? {
        if Path.isAppBundle(path: destination) && Path.infoPlist(path: destination)?.bundleID == "com.apple.dt.Xcode" {
            return InstalledXcode.init(path: destination)
        } else {
            return nil
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

public struct Network {
    private static let client = AppleAPI.Client()
    
    public var dataTask: (URLRequest) -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> = {
        AppleAPI.Current.network.session.dataTaskPublisher(for: $0)
            .mapError { $0 as Error }
            .eraseToAnyPublisher() 
    }
   
    public func dataTask(with request: URLRequest) -> AnyPublisher<URLSession.DataTaskPublisher.Output, Error> {
        dataTask(request)
    }
    
    public func dataTaskAsync(with request: URLRequest) async throws -> (Data, URLResponse) {
        return try await AppleAPI.Current.network.session.data(for: request)
    }
    
    public var downloadTask: (URL, URL, Data?) -> (Progress, AnyPublisher<(saveLocation: URL, response: URLResponse), Error>) = { AppleAPI.Current.network.session.downloadTask(with: $0, to: $1, resumingWith: $2) }

    public func downloadTask(with url: URL, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, publisher: AnyPublisher<(saveLocation: URL, response: URLResponse), Error>) {
        return downloadTask(url, saveLocation, resumeData)
    }
    
    public var validateSession: () -> AnyPublisher<Void, Error> = {
        return client.validateSession()
    }
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
public struct Helper {
    var install: () throws -> Void = helperClient.install
    var checkIfLatestHelperIsInstalled: () -> AnyPublisher<Bool, Never> = helperClient.checkIfLatestHelperIsInstalled
    var getVersion: () -> AnyPublisher<String, Error> = helperClient.getVersion
    var switchXcodePath: (_ absolutePath: String) -> AnyPublisher<Void, Error> = helperClient.switchXcodePath
    var devToolsSecurityEnable: () -> AnyPublisher<Void, Error> = helperClient.devToolsSecurityEnable
    var addStaffToDevelopersGroup: () -> AnyPublisher<Void, Error> = helperClient.addStaffToDevelopersGroup
    var acceptXcodeLicense: (_ absoluteXcodePath: String) ->  AnyPublisher<Void, Error> = helperClient.acceptXcodeLicense
    var runFirstLaunch: (_ absoluteXcodePath: String) -> AnyPublisher<Void, Error> = helperClient.runFirstLaunch
}
