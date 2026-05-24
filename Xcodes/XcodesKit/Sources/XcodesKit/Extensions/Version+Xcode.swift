import Foundation
import Version

public extension Version {
    init?(xcodeVersion: String, buildMetadataIdentifier: String? = nil) {
        let nsrange = NSRange(xcodeVersion.startIndex..<xcodeVersion.endIndex, in: xcodeVersion)
        let pattern = "^(Xcode )?(?<major>\\d+)\\.?(?<minor>\\d*)\\.?(?<patch>\\d*) ?(?<prereleaseType>[a-zA-Z ]+)? ?(?<prereleaseVersion>\\d*)"

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

        let prereleaseType = match.groupNamed("prereleaseType", in: xcodeVersion)?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }
            .filter { !$0.isEmpty } ?? []

        var optionalPrereleaseIdentifiers: [String?] = []
        prereleaseType.forEach { type in
            if type == "seed" {
                let lastIndex = optionalPrereleaseIdentifiers.endIndex - 1
                if optionalPrereleaseIdentifiers.indices.contains(lastIndex),
                   let lastItem = optionalPrereleaseIdentifiers[lastIndex] {
                    optionalPrereleaseIdentifiers[lastIndex] = "\(lastItem)-seed"
                }
            } else if type == "b" {
                optionalPrereleaseIdentifiers.append("beta")
            } else {
                optionalPrereleaseIdentifiers.append(type)
            }
        }
        optionalPrereleaseIdentifiers.append(match.groupNamed("prereleaseVersion", in: xcodeVersion))

        let prereleaseIdentifiers = optionalPrereleaseIdentifiers
            .compactMap { $0?.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }
            .filter { !$0.isEmpty }

        self = Version(major: major, minor: minor, patch: patch, prereleaseIdentifiers: prereleaseIdentifiers, buildMetadataIdentifiers: [buildMetadataIdentifier].compactMap { $0 })
    }

    init?(xcReleasesXcode: XcodeRelease) {
        var versionString = xcReleasesXcode.version.number ?? ""

        let components = versionString.components(separatedBy: ".")
        versionString += Array(repeating: ".0", count: 3 - components.count).joined()

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
            break
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

        if let buildNumber = xcReleasesXcode.version.build {
            versionString += "+\(buildNumber)"
        }

        self.init(versionString)
    }

    /// The intent here is to match Apple's marketing version.
    var appleDescription: String {
        var base = "\(major).\(minor)"
        if patch != 0 {
            base += ".\(patch)"
        }
        if !prereleaseIdentifiers.isEmpty {
            base += " " + prereleaseIdentifiers
                .map { identifier in
                    identifier
                        .replacingOccurrences(of: "-", with: " ")
                        .capitalized
                        .replacingOccurrences(of: "Gm", with: "GM")
                        .replacingOccurrences(of: "Rc", with: "RC")
                }
                .joined(separator: " ")
        }
        return base
    }

    var appleDescriptionWithBuildIdentifier: String {
        [appleDescription, buildMetadataIdentifiersDisplay].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var buildMetadataIdentifiersDisplay: String {
        !buildMetadataIdentifiers.isEmpty ? "(\(buildMetadataIdentifiers.joined(separator: " ")))" : ""
    }

    func isEquivalent(to other: Version) -> Bool {
        if buildMetadataIdentifiers.isEmpty || other.buildMetadataIdentifiers.isEmpty {
            return major == other.major &&
                   minor == other.minor &&
                   patch == other.patch &&
                   prereleaseIdentifiers.map { $0.lowercased() } == other.prereleaseIdentifiers.map { $0.lowercased() }
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

private extension NSTextCheckingResult {
    func groupNamed(_ name: String, in string: String) -> String? {
        let nsrange = range(withName: name)
        guard let range = Range(nsrange, in: string) else { return nil }
        return String(string[range])
    }
}
