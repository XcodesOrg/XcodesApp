import Foundation
import AsyncNetworkService
import Path

extension URL {
    static let downloadableRuntimes = URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!
}

public struct RuntimeService {
    var networkService: AsyncHTTPNetworkService
    public enum Error: LocalizedError, Equatable {
        case unavailableRuntime(String)
        case failedMountingDMG
    }

    public init() {
        networkService = AsyncHTTPNetworkService()
    }
    
    public func downloadableRuntimes() async throws -> DownloadableRuntimesResponse {
        let urlRequest = URLRequest(url: .downloadableRuntimes)
        
        // Apple gives a plist for download
        let (data, _) = try await networkService.requestData(urlRequest, validators: [])
        do {
            let decodedResponse = try PropertyListDecoder().decode(DownloadableRuntimesResponse.self, from: data)
            return decodedResponse
        } catch {
            print("error: \(error)")
            throw error
        }
        
    }
    
    public func installedRuntimes() async throws -> [InstalledRuntime] {
        // This only uses the Selected Xcode, so we don't know what other SDK's have been installed in previous versions
        let output = try await Current.shell.installedRuntimes()
        
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
        guard let path = Path("/Library/Developer/CoreSimulator/images/images.plist") else { throw "Could not find images.plist for CoreSimulators" }
        guard let infoPlistData = FileManager.default.contents(atPath: path.string) else { throw "Could not get data from \(path.string)" }
        
        do {
            let infoPlist: CoreSimulatorPlist = try PropertyListDecoder().decode(CoreSimulatorPlist.self, from: infoPlistData)
            return infoPlist.images
        } catch {
            throw error
        }
    }
    
    public func installRuntimeImage(dmgURL: URL) async throws {
        _ =  try await Current.shell.installRuntimeImage(dmgURL)
    }
    
    public func mountDMG(dmgUrl: URL) async throws -> URL {
        let resultPlist = try await Current.shell.mountDmg(dmgUrl)
        
        let dict = try? (PropertyListSerialization.propertyList(from: resultPlist.out.data(using: .utf8)!, format: nil) as? NSDictionary)
        let systemEntities = dict?["system-entities"] as? NSArray
        guard let path = systemEntities?.compactMap ({ ($0 as? NSDictionary)?["mount-point"] as? String }).first else {
            throw Error.failedMountingDMG
        }
        return URL(fileURLWithPath: path)
    }
    
    public func unmountDMG(mountedURL: URL) async throws {
        _ = try await Current.shell.unmountDmg(mountedURL)
    }
    
    public func expand(pkgPath: Path, expandedPkgPath: Path) async throws {
        _ = try await Current.shell.expandPkg(pkgPath.url, expandedPkgPath.url)
    }
    
    public func createPkg(pkgPath: Path, expandedPkgPath: Path) async throws {
        _ = try await Current.shell.createPkg(pkgPath.url, expandedPkgPath.url)
    }
    
    public func installPkg(pkgPath: Path, expandedPkgPath: Path) async throws {
        _ = try await Current.shell.installPkg(pkgPath.url, expandedPkgPath.url.absoluteString)
    }
    
    public func deleteRuntime(identifier: String) async throws {
        do {
            _ = try await Current.shell.deleteRuntime(identifier)
        } catch {
            if let executionError = error as? ProcessExecutionError {
                throw executionError.standardError
            }
            throw error
        }
    }
}

extension String: Error {}
