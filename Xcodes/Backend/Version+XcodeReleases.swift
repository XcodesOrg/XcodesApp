import Version
import struct XCModel.Xcode

extension Version {
    /// Initialize a Version from an XcodeReleases' XCModel.Xcode
    ///
    /// This is kinda quick-and-dirty, and it would probably be better for us to adopt something closer to XCModel.Xcode under the hood and map the scraped data to it instead.
    init?(xcReleasesXcode: XCModel.Xcode) {
        var versionString = xcReleasesXcode.version.number ?? ""
        
        // Append trailing ".0" in order to get a fully-specified version string
        let components = versionString.components(separatedBy: ".")
        versionString += Array(repeating: ".0", count: 3 - components.count).joined()
        
        // Append prerelease identifier
        switch xcReleasesXcode.version.release {
        case let .beta(beta):
            versionString += "-Beta"
            if beta > 1 {
                versionString += ".\(beta)"
            }
        case let .dp(dp):
            versionString += "-DP"
            if dp > 1 {
                versionString += ".\(dp)"
            }
        case .gm:
            versionString += "-GM"
        case let .gmSeed(gmSeed):
            versionString += "-GM.Seed"
            if gmSeed > 1 {
                versionString += ".\(gmSeed)"
            }
        case let .rc(rc):
            versionString += "-Release.Candidate"
            if rc > 1 {
                versionString += ".\(rc)"
            }
        case .release:
            break
        }
        
        // Append build identifier
        if let buildNumber = xcReleasesXcode.version.build {
            versionString += "+\(buildNumber)"
        }
        
        self.init(versionString)
    }
    
    var buildMetadataIdentifiersDisplay: String {
        return !buildMetadataIdentifiers.isEmpty ? "(\(buildMetadataIdentifiers.joined(separator: " ")))" : ""
    }
}

