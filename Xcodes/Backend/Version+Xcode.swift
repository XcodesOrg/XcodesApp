import Foundation
import Version

public extension Version {
    /**
     E.g.:
     Xcode 10.2 Beta 4
     Xcode 10.2 GM
     Xcode 10.2 GM seed 2
     Xcode 10.2
     Xcode 10.2.1
     10.2 Beta 4
     10.2 GM
     10.2
     10.2.1
     */
    init?(xcodeVersion: String, buildMetadataIdentifier: String? = nil) {
        let nsrange = NSRange(xcodeVersion.startIndex..<xcodeVersion.endIndex, in: xcodeVersion)
        // https://regex101.com/r/dLLvsz/1
        let pattern = "^(Xcode )?(?<major>\\d+)\\.?(?<minor>\\d?)\\.?(?<patch>\\d?) ?(?<prereleaseType>[a-zA-Z ]+)? ?(?<prereleaseVersion>\\d?)"

        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: xcodeVersion, options: [], range: nsrange),
            let majorString = match.groupNamed("major", in: xcodeVersion),
            let major = Int(majorString),
            let minorString = match.groupNamed("minor", in: xcodeVersion),
            let patchString = match.groupNamed("patch", in: xcodeVersion)
        else { return nil }

        let minor = Int(minorString) ?? 0
        let patch = Int(patchString) ?? 0
        let prereleaseIdentifiers = [match.groupNamed("prereleaseType", in: xcodeVersion), 
                                     match.groupNamed("prereleaseVersion", in: xcodeVersion)]
                                        .compactMap { $0?.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }
                                        .filter { !$0.isEmpty }

        self = Version(major: major, minor: minor, patch: patch, prereleaseIdentifiers: prereleaseIdentifiers, buildMetadataIdentifiers: [buildMetadataIdentifier].compactMap { $0 })
    }

    /// The intent here is to match Apple's marketing version
    ///
    /// Only show the patch number if it's not 0
    /// Format prerelease identifiers
    /// Don't include build identifiers
    var appleDescription: String {
        var base = "\(major).\(minor)"
        if patch != 0 {
            base += ".\(patch)"
        }
        if !prereleaseIdentifiers.isEmpty {
            base += " " + prereleaseIdentifiers
                .map { $0.replacingOccurrences(of: "-", with: " ").capitalized.replacingOccurrences(of: "Gm", with: "GM") }
                .joined(separator: " ")
        }
        return base
    }
}

extension NSTextCheckingResult {
    func groupNamed(_ name: String, in string: String) -> String? {
        let nsrange = range(withName: name)
        guard let range = Range(nsrange, in: string) else { return nil }
        return String(string[range])
    }
}
