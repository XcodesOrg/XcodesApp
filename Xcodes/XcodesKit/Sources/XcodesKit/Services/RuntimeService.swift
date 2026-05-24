import Foundation
@preconcurrency import Path

public extension URL {
    static let downloadableRuntimes = URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!
}

public struct RuntimeService: Sendable {
    public typealias LoadData = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias ContentsAtPath = @Sendable (String) -> Data?
    public typealias LoadShellOutput = @Sendable () async throws -> ProcessOutput
    public typealias RuntimeURLShellOutput = @Sendable (URL) async throws -> ProcessOutput
    public typealias ProcessURLShellOutput = @Sendable (URL, URL) async throws -> ProcessOutput
    public typealias InstallPackageOutput = @Sendable (URL, String) async throws -> ProcessOutput
    public typealias DeleteRuntimeOutput = @Sendable (String) async throws -> ProcessOutput

    private var loadData: LoadData
    private var contentsAtPath: ContentsAtPath
    private var installedRuntimesOutput: LoadShellOutput
    private var installRuntimeImageOutput: RuntimeURLShellOutput
    private var mountDMGOutput: RuntimeURLShellOutput
    private var unmountDMGOutput: RuntimeURLShellOutput
    private var expandPkgOutput: ProcessURLShellOutput
    private var createPkgOutput: ProcessURLShellOutput
    private var installPkgOutput: InstallPackageOutput
    private var deleteRuntimeOutput: DeleteRuntimeOutput

    public enum Error: LocalizedError, Equatable, Sendable {
        case unavailableRuntime(String)
        case failedMountingDMG
    }

    public init(urlSession: URLSession = URLSession(configuration: .ephemeral)) {
        let shell = XcodesShell()
        self.init(
            loadData: { try await urlSession.data(for: $0) },
            contentsAtPath: { path in FileManager.default.contents(atPath: path) },
            installedRuntimesOutput: { try await shell.installedRuntimes() },
            installRuntimeImageOutput: { url in try await shell.installRuntimeImage(url) },
            mountDMGOutput: { url in try await shell.mountDmg(url) },
            unmountDMGOutput: { url in try await shell.unmountDmg(url) },
            expandPkgOutput: { packageURL, destinationURL in try await shell.expandPkg(packageURL, destinationURL) },
            createPkgOutput: { packageURL, destinationURL in try await shell.createPkg(packageURL, destinationURL) },
            installPkgOutput: { packageURL, target in try await shell.installPkg(packageURL, target) },
            deleteRuntimeOutput: { identifier in try await shell.deleteRuntime(identifier) }
        )
    }

    public init(
        loadData: @escaping LoadData,
        contentsAtPath: @escaping ContentsAtPath = { path in FileManager.default.contents(atPath: path) },
        installedRuntimesOutput: @escaping LoadShellOutput,
        installRuntimeImageOutput: @escaping RuntimeURLShellOutput,
        mountDMGOutput: @escaping RuntimeURLShellOutput,
        unmountDMGOutput: @escaping RuntimeURLShellOutput,
        expandPkgOutput: @escaping ProcessURLShellOutput = { packageURL, destinationURL in try await XcodesShell().expandPkg(packageURL, destinationURL) },
        createPkgOutput: @escaping ProcessURLShellOutput = { packageURL, destinationURL in try await XcodesShell().createPkg(packageURL, destinationURL) },
        installPkgOutput: @escaping InstallPackageOutput = { packageURL, target in try await XcodesShell().installPkg(packageURL, target) },
        deleteRuntimeOutput: @escaping DeleteRuntimeOutput = { identifier in try await XcodesShell().deleteRuntime(identifier) }
    ) {
        self.loadData = loadData
        self.contentsAtPath = contentsAtPath
        self.installedRuntimesOutput = installedRuntimesOutput
        self.installRuntimeImageOutput = installRuntimeImageOutput
        self.mountDMGOutput = mountDMGOutput
        self.unmountDMGOutput = unmountDMGOutput
        self.expandPkgOutput = expandPkgOutput
        self.createPkgOutput = createPkgOutput
        self.installPkgOutput = installPkgOutput
        self.deleteRuntimeOutput = deleteRuntimeOutput
    }
    
    public func downloadableRuntimes() async throws -> DownloadableRuntimesResponse {
        let urlRequest = URLRequest(url: .downloadableRuntimes)
        
        // Apple gives a plist for download
        let (data, _) = try await loadData(urlRequest)
        return try PropertyListDecoder().decode(DownloadableRuntimesResponse.self, from: data)
    }
    
    public func installedRuntimes() async throws -> [InstalledRuntime] {
        // This only uses the Selected Xcode, so we don't know what other SDK's have been installed in previous versions
        let output = try await installedRuntimesOutput()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let outputDictionary = try decoder.decode([String: InstalledRuntime].self, from: output.out.data(using: .utf8)!)
        
        return outputDictionary.values.sorted { first, second in
            return first.identifier.uuidString.compare(second.identifier.uuidString, options: .numeric) == .orderedAscending
        }
    }
    
    /// Loops through `/Library/Developer/CoreSimulator/images/images.plist` which contains a list of downloaded Simuator Runtimes
    /// This is different then using `simctl` (`installedRuntimes()`) which only returns the installed runtimes for the selected xcode version.
    public func localInstalledRuntimes() async throws -> [CoreSimulatorImage] {
        guard let path = Path("/Library/Developer/CoreSimulator/images/images.plist") else { throw XcodesKitError("Could not find images.plist for CoreSimulators") }
        guard let infoPlistData = contentsAtPath(path.string) else { throw XcodesKitError("Could not get data from \(path.string)") }
        
        do {
            let infoPlist: CoreSimulatorPlist = try PropertyListDecoder().decode(CoreSimulatorPlist.self, from: infoPlistData)
            return infoPlist.images
        } catch {
            throw error
        }
    }
    
    public func installRuntimeImage(dmgURL: URL) async throws {
        _ = try await installRuntimeImageOutput(dmgURL)
    }
    
    public func mountDMG(dmgUrl: URL) async throws -> URL {
        let resultPlist = try await mountDMGOutput(dmgUrl)
        
        let dict = try? (PropertyListSerialization.propertyList(from: resultPlist.out.data(using: .utf8)!, format: nil) as? NSDictionary)
        let systemEntities = dict?["system-entities"] as? NSArray
        guard let path = systemEntities?.compactMap ({ ($0 as? NSDictionary)?["mount-point"] as? String }).first else {
            throw Error.failedMountingDMG
        }
        return URL(fileURLWithPath: path)
    }
    
    public func unmountDMG(mountedURL: URL) async throws {
        _ = try await unmountDMGOutput(mountedURL)
    }
    
    public func expand(pkgPath: Path, expandedPkgPath: Path) async throws {
        _ = try await expandPkgOutput(pkgPath.url, expandedPkgPath.url)
    }
    
    public func createPkg(pkgPath: Path, expandedPkgPath: Path) async throws {
        _ = try await createPkgOutput(pkgPath.url, expandedPkgPath.url)
    }
    
    public func installPkg(pkgPath: Path, expandedPkgPath: Path) async throws {
        _ = try await installPkgOutput(pkgPath.url, expandedPkgPath.url.absoluteString)
    }
    
    public func deleteRuntime(identifier: String) async throws {
        do {
            _ = try await deleteRuntimeOutput(identifier)
        } catch {
            if let executionError = error as? ProcessExecutionError {
                throw XcodesKitError(executionError.standardError)
            }
            throw error
        }
    }
}
