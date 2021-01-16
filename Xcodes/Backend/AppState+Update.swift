import Combine
import Foundation
import Path
import Version
import SwiftSoup
import struct XCModel.Xcode

extension AppState {
    private var dataSource: DataSource {
        Current.defaults.string(forKey: "dataSource").flatMap(DataSource.init(rawValue:)) ?? .default
    }
    
    func updateIfNeeded() {
        guard
            let lastUpdated = Current.defaults.date(forKey: "lastUpdated"),
            // This is bad date math but for this use case it doesn't need to be exact
            lastUpdated < Current.date().addingTimeInterval(-60 * 60 * 24) 
        else { 
            updatePublisher = updateSelectedXcodePath()
                .sink(
                    receiveCompletion: { _ in 
                        self.updatePublisher = nil
                    },
                    receiveValue: { _ in }
                )
            return
        }
        update() as Void
    }

    func update() {
        guard !isUpdating else { return }
        updatePublisher = updateSelectedXcodePath()
            .flatMap { _ in 
                self.updateAvailableXcodes(from: self.dataSource)
            }
            .sink(
                receiveCompletion: { [unowned self] completion in
                    switch completion {
                    case let .failure(error):
                        self.error = error
                    case .finished:
                        Current.defaults.setDate(Current.date(), forKey: "lastUpdated")
                    }

                    self.updatePublisher = nil
                },
                receiveValue: { _ in }
            )
    }
    
    func updateSelectedXcodePath() -> AnyPublisher<Void, Never> {
        Current.shell.xcodeSelectPrintPath()
            .handleEvents(receiveOutput: { output in self.selectedXcodePath = output.out })
            // Ignore xcode-select failures
            .map { _ in Void() }
            .catch { _ in Just(()) }
            .eraseToAnyPublisher()
    }

    private func updateAvailableXcodes(from dataSource: DataSource) -> AnyPublisher<[AvailableXcode], Error> {
        switch dataSource {
        case .apple:
            return signInIfNeeded() 
                .flatMap { [unowned self] in self.releasedXcodes().combineLatest(self.prereleaseXcodes()) }
                .receive(on: DispatchQueue.main)
                .map { releasedXcodes, prereleaseXcodes in
                    // Starting with Xcode 11 beta 6, developer.apple.com/download and developer.apple.com/download/more both list some pre-release versions of Xcode.
                    // Previously pre-release versions only appeared on developer.apple.com/download.
                    // /download/more doesn't include build numbers, so we trust that if the version number and prerelease identifiers are the same that they're the same build.
                    // If an Xcode version is listed on both sites then prefer the one on /download because the build metadata is used to compare against installed Xcodes.
                    let xcodes = releasedXcodes.filter { releasedXcode in
                        prereleaseXcodes.contains { $0.version.isEquivalent(to: releasedXcode.version) } == false
                    } + prereleaseXcodes
                    return xcodes
                }
                .handleEvents(
                    receiveOutput: { xcodes in
                        self.availableXcodes = xcodes
                        try? self.cacheAvailableXcodes(xcodes)
                    }
                )
                .eraseToAnyPublisher()
        case .xcodeReleases:
            return xcodeReleases()
                .receive(on: DispatchQueue.main)
                .handleEvents(
                    receiveOutput: { xcodes in
                        self.availableXcodes = xcodes
                        try? self.cacheAvailableXcodes(xcodes)    
                    }
                )
                .eraseToAnyPublisher()
        }
    }
}

extension AppState {
    // MARK: - Available Xcode Cache

    func loadCachedAvailableXcodes() throws {
        guard let data = Current.files.contents(atPath: Path.cacheFile.string) else { return }
        let xcodes = try JSONDecoder().decode([AvailableXcode].self, from: data)
        self.availableXcodes = xcodes
    }

    func cacheAvailableXcodes(_ xcodes: [AvailableXcode]) throws {
        let data = try JSONEncoder().encode(xcodes)
        try FileManager.default.createDirectory(at: Path.cacheFile.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: Path.cacheFile.url)
    }
}

extension AppState {
    // MARK: - Apple
    
    private func releasedXcodes() -> AnyPublisher<[AvailableXcode], Error> {
        Current.network.dataTask(with: URLRequest.downloads)
            .map(\.data)
            .decode(type: Downloads.self, decoder: configure(JSONDecoder()) {
                $0.dateDecodingStrategy = .formatted(.downloadsDateModified)
            })
            .map { downloads -> [AvailableXcode] in
                let xcodes = downloads
                    .downloads
                    .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
                    .compactMap { download -> AvailableXcode? in
                        let urlPrefix = URL(string: "https://download.developer.apple.com/")!
                        guard 
                            let xcodeFile = download.files.first(where: { $0.remotePath.hasSuffix("dmg") || $0.remotePath.hasSuffix("xip") }),
                            let version = Version(xcodeVersion: download.name)
                        else { return nil }

                        let url = urlPrefix.appendingPathComponent(xcodeFile.remotePath)
                        return AvailableXcode(version: version, url: url, filename: String(xcodeFile.remotePath.suffix(fromLast: "/")), releaseDate: download.dateModified)
                    }
                return xcodes
            }
            .eraseToAnyPublisher()
    }

    private func prereleaseXcodes() -> AnyPublisher<[AvailableXcode], Error> {
        Current.network.dataTask(with: URLRequest.download)
            .tryMap { (data, _) -> [AvailableXcode] in
                try self.parsePrereleaseXcodes(from: data)
            }
            .eraseToAnyPublisher()
    }

    private func parsePrereleaseXcodes(from data: Data) throws -> [AvailableXcode] {
        let body = String(data: data, encoding: .utf8)!
        let document = try SwiftSoup.parse(body)

        guard 
            let xcodeHeader = try document.select("h2:containsOwn(Xcode)").first(),
            let productBuildVersion = try xcodeHeader.parent()?.select("li:contains(Build)").text().replacingOccurrences(of: "Build", with: ""),
            let releaseDateString = try xcodeHeader.parent()?.select("li:contains(Released)").text().replacingOccurrences(of: "Released", with: ""),
            let version = Version(xcodeVersion: try xcodeHeader.text(), buildMetadataIdentifier: productBuildVersion),
            let path = try document.select(".direct-download[href*=xip]").first()?.attr("href"),
            let url = URL(string: "https://developer.apple.com" + path)
        else { return [] }

        let filename = String(path.suffix(fromLast: "/"))

        return [AvailableXcode(version: version, url: url, filename: filename, releaseDate: DateFormatter.downloadsReleaseDate.date(from: releaseDateString))]
    }
}

extension AppState {
    // MARK: - XcodeReleases
    
    private func xcodeReleases() -> AnyPublisher<[AvailableXcode], Error> {
        Current.network.dataTask(with: URLRequest(url: URL(string: "https://xcodereleases.com/data.json")!))
            .map(\.data)
            .decode(type: [XCModel.Xcode].self, decoder: JSONDecoder())
            .map { xcReleasesXcodes in  
                let xcodes = xcReleasesXcodes.compactMap { xcReleasesXcode -> AvailableXcode? in
                    guard
                        let downloadURL = xcReleasesXcode.links?.download?.url,
                        let version = Version(xcReleasesXcode: xcReleasesXcode)
                    else { return nil }
                    
                    let releaseDate = Calendar(identifier: .gregorian).date(from: DateComponents(
                        year: xcReleasesXcode.date.year,
                        month: xcReleasesXcode.date.month,
                        day: xcReleasesXcode.date.day
                    ))
                    
                    return AvailableXcode(
                        version: version,
                        url: downloadURL,
                        filename: String(downloadURL.path.suffix(fromLast: "/")),
                        releaseDate: releaseDate,
                        requiredMacOSVersion: xcReleasesXcode.requires,
                        releaseNotesURL: xcReleasesXcode.links?.notes?.url,
                        sdks: xcReleasesXcode.sdks,
                        compilers: xcReleasesXcode.compilers
                    )
                }
                return xcodes
            }
            .map(filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers)
            .eraseToAnyPublisher()
    }
    
    /// Xcode Releases may have multiple releases with the same build metadata when a build doesn't change between candidate and final releases.
    /// For example, 12.3 RC and 12.3 are both build 12C33
    /// We don't care about that difference, so only keep the final release (GM or Release, in XCModel terms).
    /// The downside of this is that a user could technically have both releases installed, and so they won't both be shown in the list, but I think most users wouldn't do this.
    func filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers(_ availableXcodes: [AvailableXcode]) -> [AvailableXcode] {
        var filteredAvailableXcodes: [AvailableXcode] = []
        for availableXcode in availableXcodes {
            if availableXcode.version.buildMetadataIdentifiers.isEmpty {
                filteredAvailableXcodes.append(availableXcode)
                continue
            }
            
            let availableXcodesWithSameBuildMetadataIdentifiers = availableXcodes
                .filter({ $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers })
            if availableXcodesWithSameBuildMetadataIdentifiers.count > 1,
               availableXcode.version.prereleaseIdentifiers.isEmpty || availableXcode.version.prereleaseIdentifiers == ["GM"] {
                filteredAvailableXcodes.append(availableXcode)
            } else if availableXcodesWithSameBuildMetadataIdentifiers.count == 1 {
                filteredAvailableXcodes.append(availableXcode)
            }
        }
        return filteredAvailableXcodes
    } 
}
