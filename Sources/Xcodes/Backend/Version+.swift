import Version

public extension Version {
    /// Determines if two Xcode versions should be treated equivalently. This is not the same as equality.
    /// 
    /// We need a way to determine if two Xcode versions are the same without always having full information, and supporting different data sources.
    /// For example, the Apple data source often doesn't have build metadata identifiers.  
    func isEquivalent(to other: Version) -> Bool {
        // If we don't have build metadata identifiers for both Versions, compare major, minor, patch and prerelease identifiers.
        if buildMetadataIdentifiers.isEmpty || other.buildMetadataIdentifiers.isEmpty {
            return major == other.major &&
                   minor == other.minor &&
                   patch == other.patch &&
                   prereleaseIdentifiers.map { $0.lowercased() } == other.prereleaseIdentifiers.map { $0.lowercased() }
        // If we have build metadata identifiers for both, we can ignore the prerelease identifiers.
        } else {
            return major == other.major &&
                   minor == other.minor &&
                   patch == other.patch && 
                   buildMetadataIdentifiers.map { $0.lowercased() } == other.buildMetadataIdentifiers.map { $0.lowercased() }
        }
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
