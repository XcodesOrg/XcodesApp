import Foundation
import XcodesKit
import Version

/// The platforms whose simulator runtimes should be kept installed automatically.
///
/// Stored as a comma separated list of platform identifiers so that it round trips
/// through `@AppStorage` and through a managed preference profile.
struct AutoInstallRuntimePlatforms: RawRepresentable, Equatable {
    /// The platforms that can be installed automatically.
    ///
    /// macOS is excluded because there is no downloadable macOS simulator runtime.
    static let availablePlatforms: [DownloadableRuntime.Platform] = [.iOS, .watchOS, .tvOS, .visionOS]

    var platforms: Set<DownloadableRuntime.Platform>

    init(platforms: Set<DownloadableRuntime.Platform> = []) {
        self.platforms = platforms
    }

    init?(rawValue: String) {
        self.platforms = Set(
            rawValue
                .split(separator: ",")
                .compactMap { DownloadableRuntime.Platform(rawValue: String($0)) }
        )
    }

    var rawValue: String {
        platforms.sorted(\.order)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    func contains(_ platform: DownloadableRuntime.Platform) -> Bool {
        platforms.contains(platform)
    }

    mutating func setContains(_ contains: Bool, for platform: DownloadableRuntime.Platform) {
        if contains {
            platforms.insert(platform)
        } else {
            platforms.remove(platform)
        }
    }
}

/// Decides which simulator runtimes should be installed automatically once an
/// Xcode installation finishes.
struct RuntimeAutoInstallService {
    /// Returns the newest downloadable runtime for each requested platform.
    ///
    /// A platform is skipped when its newest runtime is already installed, so that
    /// repeated Xcode installs don't re-download runtimes that are already on disk.
    func runtimesToInstall(
        platforms: Set<DownloadableRuntime.Platform>,
        downloadableRuntimes: [DownloadableRuntime],
        installedRuntimes: [CoreSimulatorImage],
        includingPrereleases: Bool
    ) -> [DownloadableRuntime] {
        guard !platforms.isEmpty else { return [] }

        let installedBuilds = Set(installedRuntimes.map(\.runtimeInfo.build))

        return platforms.sorted(\.order).compactMap { platform in
            let candidates = downloadableRuntimes.filter { runtime in
                runtime.platform == platform && (includingPrereleases || runtime.betaNumber == nil)
            }

            guard let newest = candidates.max(by: isOlder) else { return nil }
            guard !installedBuilds.contains(newest.simulatorVersion.buildUpdate) else { return nil }

            return newest
        }
    }

    /// Orders two runtimes of the same platform, newest last.
    private func isOlder(_ lhs: DownloadableRuntime, _ rhs: DownloadableRuntime) -> Bool {
        let lhsVersion = Version(tolerant: lhs.simulatorVersion.version) ?? Version(0, 0, 0)
        let rhsVersion = Version(tolerant: rhs.simulatorVersion.version) ?? Version(0, 0, 0)

        guard lhsVersion == rhsVersion else { return lhsVersion < rhsVersion }

        // A release of a version always wins over a beta of the same version,
        // otherwise the higher seed number wins.
        return (lhs.betaNumber ?? .max) < (rhs.betaNumber ?? .max)
    }
}
