import Foundation
import Version
import XcodesKit

extension Version {
    /// Initialize a Version from an XcodeReleases' XCModel.Xcode
    ///
    /// This is kinda quick-and-dirty, and it would probably be better for us to adopt something closer to XCModel.Xcode
    /// under the hood and map the scraped data to it instead.
    init?(xcReleasesXcode: XcodeRelease) {
        var versionString = xcReleasesXcode.version.number ?? ""

        // Append trailing ".0" in order to get a fully-specified version string
        let components = versionString.components(separatedBy: ".")
        versionString += Array(repeating: ".0", count: 3 - components.count).joined()

        // Append prerelease identifier
        versionString += xcReleasesXcode.version.release.versionPrereleaseIdentifier

        // Append build identifier
        if let buildNumber = xcReleasesXcode.version.build {
            versionString += "+\(buildNumber)"
        }

        self.init(versionString)
    }

    var buildMetadataIdentifiersDisplay: String {
        !buildMetadataIdentifiers.isEmpty ? "(\(buildMetadataIdentifiers.joined(separator: " ")))" : ""
    }
}

private extension Release {
    var versionPrereleaseIdentifier: String {
        switch self {
        case let .beta(beta):
            prereleaseIdentifier("-Beta", version: beta)
        case let .developerPreview(developerPreview):
            prereleaseIdentifier("-DP", version: developerPreview)
        case .gmRelease:
            ""
        case let .gmSeed(gmSeed):
            prereleaseIdentifier("-GM.Seed", version: gmSeed)
        case let .releaseCandidate(releaseCandidate):
            prereleaseIdentifier("-Release.Candidate", version: releaseCandidate)
        case .release:
            ""
        }
    }

    private func prereleaseIdentifier(_ identifier: String, version: Int) -> String {
        version > 1 ? "\(identifier).\(version)" : identifier
    }
}
