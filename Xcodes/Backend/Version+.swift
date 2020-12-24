import Version

public extension Version {
    func isEqualWithoutBuildMetadataIdentifiers(to other: Version) -> Bool {
        return major == other.major && 
               minor == other.minor &&
               patch == other.patch &&
               prereleaseIdentifiers == other.prereleaseIdentifiers
    }

    /// If release versions, don't compare build metadata because that's not provided in the /downloads/more list
    /// if beta versions, compare build metadata because it's available in versions.plist
    func isEquivalentForDeterminingIfInstalled(toInstalled installed: Version) -> Bool {
        let isBeta = !prereleaseIdentifiers.isEmpty
        let otherIsBeta = !installed.prereleaseIdentifiers.isEmpty

        if isBeta && otherIsBeta {
            if buildMetadataIdentifiers.isEmpty {
                return major == installed.major &&
                       minor == installed.minor &&
                       patch == installed.patch &&
                       prereleaseIdentifiers.map { $0.lowercased() } == installed.prereleaseIdentifiers.map { $0.lowercased() }
            }
            else {
                return major == installed.major &&
                       minor == installed.minor &&
                       patch == installed.patch &&
                       prereleaseIdentifiers.map { $0.lowercased() } == installed.prereleaseIdentifiers.map { $0.lowercased() } &&
                       buildMetadataIdentifiers.map { $0.lowercased() } == installed.buildMetadataIdentifiers.map { $0.lowercased() }
            }
        }
        else if !isBeta && !otherIsBeta {
            return major == installed.major && 
                   minor == installed.minor &&
                   patch == installed.patch
        }

        return false
    }

    var descriptionWithoutBuildMetadata: String {
        var base = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            base += "-" + prereleaseIdentifiers.joined(separator: ".")
        }
        return base
    }

    var isPrerelease: Bool { prereleaseIdentifiers.isEmpty == false }
    var isNotPrerelease: Bool { prereleaseIdentifiers.isEmpty == true }
}
