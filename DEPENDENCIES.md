# Dependencies

This inventory documents direct package dependencies that affect application
builds. Branch-based direct dependencies are not allowed unless the pin has a
documented owner, reason, and replacement or release plan in this file.

SwiftPM dependency updates are handled by Dependabot for the Xcode project and
for each local package. Bundler updates for the AppCast Jekyll site are handled
by Dependabot as well. Required attributions are maintained statically in
`Xcodes/Resources/Licenses.md`; update that file when dependencies are added,
removed, or relicensed.

## Local Package Boundaries

The app project owns UI, update, install, and distribution concerns. It depends
on the local packages below instead of letting those packages import app code.

| Package | Boundary | External dependencies |
| --- | --- | --- |
| `AppleAPI` | Apple authentication and Apple API client code. | Owns `swift-srp` because SRP is only needed by this API client. |
| `XcodesKit` | Reusable Xcode release, runtime, and shell models. | Owns `Path.swift` for runtime service and shell path handling. Keep this aligned with the app-level `Path.swift` pin while both scopes use the package. |

## SwiftPM

| Scope | Package | Owner | Version model | Purpose | Replacement notes |
| --- | --- | --- | --- | --- | --- |
| Xcode project | `DockProgress` | `sindresorhus` | SemVer, `upToNextMajorVersion` from `5.1.0` | Shows install progress in the Dock tile. | Replaceable with a small `NSDockTile` drawing implementation if the dependency stops receiving updates. |
| Xcode project | `Path.swift` | `mxcl` | SemVer, `upToNextMajorVersion` from `1.6.0` | Provides path composition and filesystem convenience APIs across app code and tests. | Replacing it would touch broad filesystem code; prefer keeping it unless a larger path-handling refactor is planned. |
| Xcode project | `Sparkle` | `sparkle-project` | SemVer, `upToNextMajorVersion` from `2.9.1` | Provides direct-distribution app update checks and installation. | Keep unless distribution moves fully to the Mac App Store or another updater. |
| Xcode project | `swift-collections` | `apple` | SemVer, `upToNextMajorVersion` from `1.5.0` | Provides `OrderedDictionary` for predictable runtime grouping. | Easy to replace with arrays plus dictionaries, but the current dependency is low-risk and maintained by Apple. |
| Xcode project | `SwiftSoup` | `scinfu` | SemVer, `upToNextMajorVersion` from `2.9.6`; resolved at `2.13.4` | Parses Apple prerelease HTML when building available Xcode metadata. | Replace only with a more stable Apple data source or a maintained HTML parser. |
| Xcode project | `Version` | `mxcl` | SemVer, `upToNextMajorVersion` from `2.2.1` | Parses, compares, and formats Xcode version values. | A local parser is possible but would need careful prerelease and build-metadata coverage. |
| `AppleAPI` | `swift-srp` | `adam-fowler` | SemVer, `from: "2.3.0"` | Implements SRP authentication used by the Apple API client. | Replacement would be a security-sensitive auth rewrite; prefer a maintained release or controlled fork if needed. |
| `XcodesKit` | `Path.swift` | `mxcl` | SemVer, `from: "1.6.0"` | Provides path handling in runtime service and shell wrappers. | Keep aligned with the app-level `Path.swift` requirement. |

## Transitive SwiftPM Dependencies

| Package | Pulled in by | Purpose |
| --- | --- | --- |
| `big-num` | `swift-srp` | Big integer arithmetic for SRP. |
| `swift-asn1` | `swift-crypto` | ASN.1 support used by Swift Crypto. |
| `swift-crypto` | `swift-srp` | Cryptographic primitives used by SRP authentication. |

## Bundler

| Scope | Package | Version model | Purpose |
| --- | --- | --- | --- |
| `AppCast` | `jekyll` | `~> 4.4.1` | Builds the Sparkle appcast site. |
| `AppCast` | `jekyll-github-metadata` | Latest compatible Bundler resolution | Adds GitHub release metadata to the appcast build. |
| `AppCast` | `kramdown-parser-gfm` | Latest compatible Bundler resolution | Parses GitHub-flavored Markdown for Jekyll content. |
| `AppCast` | `tzinfo`, `tzinfo-data`, `wdm` | Platform-specific constraints | Support Windows or alternate Ruby environments for local Jekyll usage. |
