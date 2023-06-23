import Foundation
import AsyncNetworkService
import Path

extension URL {
    static let downloadableRuntimes = URL(string: "https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex")!
}

public struct RuntimeService {
    var networkService: AsyncHTTPNetworkService

    public init() {
        networkService = AsyncHTTPNetworkService()
    }
    
    public func downloadableRuntimes() async throws -> DownloadableRuntimesResponse {
        let urlRequest = URLRequest(url: .downloadableRuntimes)
        
        // Apple gives a plist for download
        let (data, _) = try await networkService.requestData(urlRequest, validators: [])
        let decodedResponse = try PropertyListDecoder().decode(DownloadableRuntimesResponse.self, from: data)

        return decodedResponse
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
    
    

}

extension String: Error {}
