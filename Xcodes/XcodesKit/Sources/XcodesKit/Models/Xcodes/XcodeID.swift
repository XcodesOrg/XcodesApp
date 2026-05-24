import Foundation
@preconcurrency import Version

public struct XcodeID: Codable, Hashable, Identifiable, Sendable {
    public let version: Version
    public let architectures: [Architecture]?

    public var id: String {
        let architectures = architectures?.map(\.rawValue).joined() ?? ""
        return version.description + architectures
    }

    public init(version: Version, architectures: [Architecture]? = nil) {
        self.version = version
        self.architectures = architectures
    }
}
