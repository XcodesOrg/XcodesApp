import Foundation
@preconcurrency import Path
@preconcurrency import Version

/// A version of Xcode that's already installed.
public struct InstalledXcode: Equatable, Sendable {
    public typealias ContentsAtPath = @Sendable (String) -> Data?
    public typealias LoadArchitectures = @Sendable (URL) throws -> ProcessOutput

    public let path: Path
    public let xcodeID: XcodeID

    /// Composed of the bundle short version from Info.plist and the product build version from version.plist.
    public var version: Version {
        xcodeID.version
    }

    public init(path: Path, version: Version, architectures: [Architecture]? = nil) {
        self.path = path
        self.xcodeID = XcodeID(version: version, architectures: architectures)
    }

    public init?(path: Path) {
        self.init(
            path: path,
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            loadArchitectures: Current.shell.archs
        )
    }

    public init?(
        path: Path,
        contentsAtPath: ContentsAtPath,
        loadArchitectures: LoadArchitectures
    ) {
        guard
            let bundle = XcodeBundleInfo(path: path, contentsAtPath: contentsAtPath),
            bundle.bundleID == "com.apple.dt.Xcode"
        else { return nil }
        self.path = bundle.path

        let xcodeBinaryURL = path.url.appending(path: "Contents/MacOS/Xcode")
        let archsString = try? loadArchitectures(xcodeBinaryURL).out
        let architectures = archsString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .compactMap { Architecture(rawValue: String($0)) }

        self.xcodeID = XcodeID(version: bundle.version, architectures: architectures)
    }
}

public extension Array where Element == InstalledXcode {
    /// Returns the first installed Xcode that unambiguously has the same version as `version`.
    func first(withVersion version: Version) -> InstalledXcode? {
        XcodeVersionMatcher.find(version: version, in: self, versionKeyPath: \InstalledXcode.version)
    }
}
