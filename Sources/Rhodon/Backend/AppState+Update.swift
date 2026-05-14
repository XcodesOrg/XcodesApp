import AppleAPI
import Foundation
import Path
import SwiftSoup
import Version
import RhodonKit

extension AppState {
    var isReadyForUpdate: Bool {
        guard
            let lastUpdated = current.defaults.date(forKey: "lastUpdated"),
            // This is bad date math but for this use case it doesn't need to be exact
            lastUpdated < current.date().addingTimeInterval(-60 * 60 * 5)
        else {
            return false
        }
        return true
    }

    func updateIfNeeded() {
        guard
            isReadyForUpdate
        else {
            updateTask = Task {
                await updateSelectedXcodePath()
                updateTask = nil
            }
            return
        }
        update() as Void
    }

    func update() {
        guard !isUpdating else { return }
        updateTask = Task {
            do {
                async let downloadableRuntimes: Void = updateDownloadableRuntimes()
                async let installedRuntimes: Void = updateInstalledRuntimes()
                await updateSelectedXcodePath()
                _ = try await updateAvailableRhodon(from: dataSource)
                _ = await (downloadableRuntimes, installedRuntimes)
                current.defaults.setDate(current.date(), forKey: "lastUpdated")
            } catch {
                if error as? AuthenticationError != .invalidSession {
                    self.error = error
                    presentedAlert = .generic(
                        title: "Unable to update selected Xcode",
                        message: error.legibleLocalizedDescription
                    )
                }
            }
            updateTask = nil
        }
    }

    func updateSelectedXcodePath() async {
        do {
            selectedXcodePath = try await current.shell.xcodeSelectPrintPath().out
        } catch {
            // Ignore xcode-select failures.
        }
    }

    private func updateAvailableRhodon(from dataSource: DataSource) async throws -> [AvailableXcode] {
        switch dataSource {
        case .apple:
            try await authenticationStore.signInIfNeeded()
            try await authenticationStore.validateSession()
            async let released = releasedRhodon()
            async let prerelease = prereleaseRhodon()
            let (releasedRhodon, prereleaseRhodon) = try await (released, prerelease)
            let rhodon = releasedRhodon.filter { releasedXcode in
                prereleaseRhodon.contains { $0.version.isEquivalent(to: releasedXcode.version) } == false
            } + prereleaseRhodon
            availableRhodon = rhodon
            try? cacheAvailableRhodon(rhodon)
            return rhodon
        case .xcodeReleases:
            let rhodon = try await xcodeReleases()
            availableRhodon = rhodon
            try? cacheAvailableRhodon(rhodon)
            return rhodon
        }
    }
}

extension AppState {
    // MARK: - Available Xcode Cache

    func loadCachedAvailableRhodon() throws {
        guard let data = current.files.contents(atPath: Path.cacheFile.string) else { return }
        let rhodon = try JSONDecoder().decode([AvailableXcode].self, from: data)
        availableRhodon = rhodon
    }

    func cacheAvailableRhodon(_ rhodon: [AvailableXcode]) throws {
        let data = try JSONEncoder().encode(rhodon)
        try FileManager.default.createDirectory(
            at: Path.cacheFile.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: Path.cacheFile.url)
    }

    // MARK: Runtime Cache

    func loadCacheDownloadableRuntimes() throws {
        guard let data = current.files.contents(atPath: Path.runtimeCacheFile.string) else { return }
        let runtimes = try JSONDecoder().decode([DownloadableRuntime].self, from: data)
        downloadableRuntimes = runtimes
    }

    func cacheDownloadableRuntimes(_ runtimes: [DownloadableRuntime]) throws {
        let data = try JSONEncoder().encode(runtimes)
        try FileManager.default.createDirectory(
            at: Path.runtimeCacheFile.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: Path.runtimeCacheFile.url)
    }
}

extension AppState {
    // MARK: - Apple

    private func releasedRhodon() async throws -> [AvailableXcode] {
        let data = try await current.network.data(for: URLRequest.downloads).0
        let downloads = try configure(JSONDecoder()) {
            $0.dateDecodingStrategy = .formatted(.downloadsDateModified)
        }.decode(Downloads.self, from: data)
        if downloads.hasError {
            throw AuthenticationError.invalidResult(resultString: downloads.resultsString)
        }
        guard let downloadList = downloads.downloads else {
            throw AuthenticationError.invalidResult(resultString: "No download information found")
        }
        return downloadList
            .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
            .compactMap { download -> AvailableXcode? in
                let urlPrefix = URL(string: "https://download.developer.apple.com/")!
                guard
                    let xcodeFile = download.files
                        .first(where: { $0.remotePath.hasSuffix("dmg") || $0.remotePath.hasSuffix("xip") }),
                    let version = Version(xcodeVersion: download.name)
                else { return nil }

                let url = urlPrefix.appendingPathComponent(xcodeFile.remotePath)
                return AvailableXcode(
                    version: version,
                    url: url,
                    filename: String(xcodeFile.remotePath.suffix(fromLast: "/")),
                    releaseDate: download.dateModified,
                    fileSize: xcodeFile.fileSize
                )
            }
    }

    private func prereleaseRhodon() async throws -> [AvailableXcode] {
        let data = try await current.network.data(for: URLRequest.download).0
        return try parsePrereleaseRhodon(from: data)
    }

    private func parsePrereleaseRhodon(from data: Data) throws -> [AvailableXcode] {
        let body = String(data: data, encoding: .utf8)!
        let document = try SwiftSoup.parse(body)

        guard
            let xcodeHeader = try document.select("h2:containsOwn(Xcode)").first(),
            let productBuildVersion = try xcodeHeader.parent()?.select("li:contains(Build)").text()
                .replacingOccurrences(
                    of: "Build",
                    with: ""
                ),
            let releaseDateString = try xcodeHeader.parent()?.select("li:contains(Released)").text()
                .replacingOccurrences(
                    of: "Released",
                    with: ""
                ),
            let version = try Version(xcodeVersion: xcodeHeader.text(), buildMetadataIdentifier: productBuildVersion),
            let path = try document.select(".direct-download[href*=xip]").first()?.attr("href"),
            let url = URL(string: "https://developer.apple.com" + path)
        else { return [] }

        let filename = String(path.suffix(fromLast: "/"))

        return [AvailableXcode(
            version: version,
            url: url,
            filename: filename,
            releaseDate: DateFormatter.downloadsReleaseDate.date(from: releaseDateString)
        )]
    }
}

extension AppState {
    // MARK: - XcodeReleases

    private func xcodeReleases() async throws -> [AvailableXcode] {
        let xcodeReleasesURL = URL(string: "https://xcodereleases.com/data.json")!
        let data = try await current.network.data(for: URLRequest(url: xcodeReleasesURL)).0
        let xcReleasesRhodon = try JSONDecoder().decode([XcodeRelease].self, from: data)
        return xcReleasesRhodon.compactMap { xcReleasesXcode -> AvailableXcode? in
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
                compilers: xcReleasesXcode.compilers,
                architectures: xcReleasesXcode.architectures
            )
        }
    }
}
