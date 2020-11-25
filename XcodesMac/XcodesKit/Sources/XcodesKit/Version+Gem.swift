import Foundation
import Version

public extension Version {
    /**
     Attempts to parse Gem::Version representations.

     E.g.:
     9.2b3
     9.1.2
     9.2
     9

     Doesn't handle GM prerelease identifier
     */
    init?(gemVersion: String) {
        let nsrange = NSRange(gemVersion.startIndex..<gemVersion.endIndex, in: gemVersion)
        let pattern = "^(?<major>\\d+)\\.?(?<minor>\\d?)?\\.?(?<patch>\\d?)?\\.?(?<prereleaseType>\\w?)?\\.?(?<prereleaseVersion>\\d?)"

        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: gemVersion, options: [], range: nsrange),
            let majorString = match.groupNamed("major", in: gemVersion),
            let major = Int(majorString),
            let minorString = match.groupNamed("minor", in: gemVersion),
            let patchString = match.groupNamed("patch", in: gemVersion)
        else { return nil }

        let minor = Int(minorString) ?? 0
        let patch = Int(patchString) ?? 0
        let prereleaseIdentifiers = [match.groupNamed("prereleaseType", in: gemVersion),
                                     match.groupNamed("prereleaseVersion", in: gemVersion)]
                                        .compactMap { $0 }
                                        .filter { !$0.isEmpty }
                                        .map { identifier -> String in
                                            switch identifier.lowercased() {
                                            case "a": return "Alpha"
                                            case "b": return "Beta"
                                            default: return identifier
                                            }
                                        }

        self = Version(major: major, minor: minor, patch: patch, prereleaseIdentifiers: prereleaseIdentifiers)
    }
}