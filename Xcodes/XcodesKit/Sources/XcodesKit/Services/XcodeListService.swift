import Foundation
import SwiftSoup
import Version

extension URL {
    static let developerDownload = URL(string: "https://developer.apple.com/download")!
    static let developerDownloads = URL(string: "https://developer.apple.com/services-account/QH65B2/downloadws/listDownloads.action")!
    static let xcodeReleasesData = URL(string: "https://xcodereleases.com/data.json")!
}

public extension URLRequest {
    static var developerDownload: URLRequest {
        URLRequest(url: .developerDownload)
    }

    static var developerDownloads: URLRequest {
        var request = URLRequest(url: .developerDownloads)
        request.httpMethod = "POST"
        return request
    }

    static var xcodeReleasesData: URLRequest {
        URLRequest(url: .xcodeReleasesData)
    }
}

public enum DataSource: String, CaseIterable, Identifiable, CustomStringConvertible, Sendable {
    case apple
    case xcodeReleases

    public var id: Self { self }

    public static var `default`: Self { .xcodeReleases }

    public var description: String {
        switch self {
        case .apple:
            return "Apple"
        case .xcodeReleases:
            return "Xcode Releases"
        }
    }
}

public typealias XcodeListDataSource = DataSource

public struct XcodeListService: Sendable {
    public typealias LoadData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum Error: LocalizedError, Equatable, Sendable {
        case invalidResult(String?)

        public var errorDescription: String? {
            switch self {
            case let .invalidResult(result):
                return result ?? "Downloading error"
            }
        }
    }

    private var loadData: LoadData

    public init(urlSession: URLSession = URLSession(configuration: .ephemeral)) {
        self.loadData = { request in
            try await urlSession.data(for: request)
        }
    }

    public init(loadData: @escaping LoadData) {
        self.loadData = loadData
    }

    public func availableXcodes(from dataSource: XcodeListDataSource) async throws -> [AvailableXcodeRelease] {
        switch dataSource {
        case .apple:
            async let released = releasedXcodes()
            async let prerelease = prereleaseXcodes()
            let (releasedXcodes, prereleaseXcodes) = try await (released, prerelease)

            return releasedXcodes.filter { releasedXcode in
                prereleaseXcodes.contains { $0.version.isEquivalent(to: releasedXcode.version) } == false
            } + prereleaseXcodes
        case .xcodeReleases:
            return try await xcodeReleases()
        }
    }

    public func releasedXcodes() async throws -> [AvailableXcodeRelease] {
        let downloads = try await developerDownloads()
        let downloadList = try validate(downloads, missingDownloadsMessage: "Downloading error")

        let urlPrefix = URL(string: "https://download.developer.apple.com/")!
        return downloadList
            .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
            .compactMap { download -> AvailableXcodeRelease? in
                guard
                    let xcodeFile = download.files.first(where: { $0.remotePath.hasSuffix("dmg") || $0.remotePath.hasSuffix("xip") }),
                    let version = Version(xcodeVersion: download.name)
                else { return nil }

                let url = urlPrefix.appendingPathComponent(xcodeFile.remotePath)
                return AvailableXcodeRelease(
                    version: version,
                    url: url,
                    filename: String(xcodeFile.remotePath.suffix(fromLast: "/")),
                    releaseDate: download.dateModified,
                    fileSize: xcodeFile.fileSize
                )
            }
    }

    public func validateDeveloperDownloads(missingDownloadsMessage: String = "Downloading error") async throws {
        let downloads = try await developerDownloads()
        _ = try validate(downloads, missingDownloadsMessage: missingDownloadsMessage)
    }

    public func developerDownloads() async throws -> Downloads {
        let (data, _) = try await loadData(.developerDownloads)
        return try JSONDecoder.downloads.decode(Downloads.self, from: data)
    }

    private func validate(_ downloads: Downloads, missingDownloadsMessage: String) throws -> [Download] {
        if downloads.hasError {
            throw Error.invalidResult(downloads.resultsString)
        }
        guard let downloadList = downloads.downloads else {
            throw Error.invalidResult(missingDownloadsMessage)
        }
        return downloadList
    }

    public func prereleaseXcodes() async throws -> [AvailableXcodeRelease] {
        let (data, _) = try await loadData(.developerDownload)
        return try Self.parsePrereleaseXcodes(from: data)
    }

    public func xcodeReleases() async throws -> [AvailableXcodeRelease] {
        let (data, _) = try await loadData(.xcodeReleasesData)
        let releases = try JSONDecoder().decode([XcodeRelease].self, from: data)

        return releases.compactMap { release -> AvailableXcodeRelease? in
            guard
                let downloadURL = release.links?.download?.url,
                let version = Version(xcReleasesXcode: release)
            else { return nil }

            let releaseDate = Calendar(identifier: .gregorian).date(from: DateComponents(
                year: release.date.year,
                month: release.date.month,
                day: release.date.day
            ))

            return AvailableXcodeRelease(
                version: version,
                url: downloadURL,
                filename: String(downloadURL.path.suffix(fromLast: "/")),
                releaseDate: releaseDate,
                requiredMacOSVersion: release.requires,
                releaseNotesURL: release.links?.notes?.url,
                sdks: release.sdks,
                compilers: release.compilers,
                architectures: release.architectures
            )
        }
    }

    public static func parsePrereleaseXcodes(from data: Data) throws -> [AvailableXcodeRelease] {
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

        return [
            AvailableXcodeRelease(
                version: version,
                url: url,
                filename: String(path.suffix(fromLast: "/")),
                releaseDate: DateFormatter.downloadsReleaseDate.date(from: releaseDateString)
            )
        ]
    }

    public static func filteringPrereleasesWithDuplicateBuildMetadata(_ xcodes: [AvailableXcode]) -> [AvailableXcode] {
        xcodes.filter { availableXcode in
            guard !availableXcode.version.buildMetadataIdentifiers.isEmpty else { return true }

            let availableXcodesWithIdenticalBuildIdentifiers = xcodes.filter {
                $0.version.buildMetadataIdentifiers == availableXcode.version.buildMetadataIdentifiers
            }

            return availableXcodesWithIdenticalBuildIdentifiers.count == 1 ||
                availableXcodesWithIdenticalBuildIdentifiers.count > 1 &&
                (availableXcode.version.prereleaseIdentifiers.isEmpty || availableXcode.architectures?.isEmpty == false)
        }
    }

    public static func identicalBuildIDs(for xcode: AvailableXcode, in xcodes: [AvailableXcode]) -> [XcodeID] {
        let prereleaseAvailableXcodesWithIdenticalBuildIdentifiers = xcodes.filter {
            $0.version.buildMetadataIdentifiers == xcode.version.buildMetadataIdentifiers &&
                !$0.version.prereleaseIdentifiers.isEmpty &&
                !$0.version.buildMetadataIdentifiers.isEmpty
        }

        guard !prereleaseAvailableXcodesWithIdenticalBuildIdentifiers.isEmpty,
              xcode.version.prereleaseIdentifiers.isEmpty
        else { return [] }

        return [xcode.xcodeID] + prereleaseAvailableXcodesWithIdenticalBuildIdentifiers.map(\.xcodeID)
    }
}

private extension JSONDecoder {
    static var downloads: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.downloadsDateModified)
        return decoder
    }
}
