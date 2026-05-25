import Foundation

public func makeRuntimeVersion(for osVersion: String, betaNumber: Int?) -> String {
    let betaSuffix = betaNumber.flatMap { "-beta\($0)" } ?? ""
    return osVersion + betaSuffix
}

public struct DownloadableRuntimesResponse: Codable, Sendable {
    public let sdkToSimulatorMappings: [SDKToSimulatorMapping]
    public let sdkToSeedMappings: [SDKToSeedMapping]
    public let refreshInterval: Int
    public let downloadables: [DownloadableRuntime]
    public let version: String
}

public struct DownloadableRuntime: Codable, Identifiable, Hashable, Sendable {
    public let category: Category
    public let simulatorVersion: SimulatorVersion
    public let source: String?
    public let architectures: [Architecture]?
    public let dictionaryVersion: Int
    public let contentType: ContentType
    public let platform: Platform
    public let identifier: String
    public let version: String
    public let fileSize: Int
    public let hostRequirements: HostRequirements?
    public let name: String
    public let authentication: Authentication?
    public var url: URL? {
        if let source {
            return URL(string: source)!
        }
        return nil
    }
    public var downloadPath: String? {
        url?.path
    }
    
    // dynamically updated - not decoded
    public var installState: RuntimeInstallState = .notInstalled
    public var sdkBuildUpdate: [String]?
    
    enum CodingKeys: CodingKey {
        case category
        case simulatorVersion
        case source
        case dictionaryVersion
        case contentType
        case platform
        case identifier
        case version
        case fileSize
        case hostRequirements
        case name
        case authentication
        case sdkBuildUpdate
        case architectures
    }

    public var betaNumber: Int? {
        enum Regex { static let shared = try! NSRegularExpression(pattern: "b[0-9]+") }
        guard var foundString = Regex.shared.firstString(in: identifier) else { return nil }
        foundString.removeFirst()
        return Int(foundString)!
    }

    public var completeVersion: String {
        makeRuntimeVersion(for: simulatorVersion.version, betaNumber: betaNumber)
    }

    public var visibleIdentifier: String {
        return platform.shortName + " " + completeVersion
    }
    
    public func makeVersion(for osVersion: String, betaNumber: Int?) -> String {
        makeRuntimeVersion(for: osVersion, betaNumber: betaNumber)
    }
    
    public var downloadFileSizeString: String {
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    public var id: String {
        return visibleIdentifier
    }
    
    public static func == (lhs: DownloadableRuntime, rhs: DownloadableRuntime) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

public struct SDKToSeedMapping: Codable, Sendable {
    public let buildUpdate: String
    public let platform: DownloadableRuntime.Platform
    public let seedNumber: Int
}

public struct SDKToSimulatorMapping: Codable, Sendable {
    public let sdkBuildUpdate: String
    public let simulatorBuildUpdate: String
    public let sdkIdentifier: String
    public let downloadableIdentifiers: [String]?
}

extension DownloadableRuntime {
    public struct SimulatorVersion: Codable, Hashable, Sendable {
        public let buildUpdate: String
        public let version: String
    }

    public struct HostRequirements: Codable, Hashable, Sendable {
        public let maxHostVersion: String?
        public let excludedHostArchitectures: [String]?
        public let minHostVersion: String?
        public let minXcodeVersion: String?
    }

    public enum Authentication: String, Codable, Sendable {
        case virtual = "virtual"
    }

    public enum Category: String, Codable, Sendable {
        case simulator = "simulator"
    }

    public enum ContentType: String, Codable, Sendable {
        case diskImage = "diskImage"
        case package = "package"
        case cryptexDiskImage = "cryptexDiskImage"
        case patchableCryptexDiskImage = "patchableCryptexDiskImage"
    }

    public enum Platform: String, Codable, Sendable {
        case iOS = "com.apple.platform.iphoneos"
        case macOS = "com.apple.platform.macosx"
        case watchOS = "com.apple.platform.watchos"
        case tvOS = "com.apple.platform.appletvos"
        case visionOS = "com.apple.platform.xros"
        
        public var order: Int {
            switch self {
                case .iOS: return 1
                case .macOS: return 2
                case .watchOS: return 3
                case .tvOS: return 4
                case .visionOS: return 5
            }
        }

        public var shortName: String {
            switch self {
                case .iOS: return "iOS"
                case .macOS: return "macOS"
                case .watchOS: return "watchOS"
                case .tvOS: return "tvOS"
                case .visionOS: return "visionOS"
            }
        }
        
    }
}

public struct InstalledRuntime: Decodable, Sendable {
    public let build: String
    public let deletable: Bool
    public let identifier: UUID
    public let kind: Kind
    public let lastUsedAt: Date?
    public let path: String
    public let platformIdentifier: Platform
    public let runtimeBundlePath: String
    public let runtimeIdentifier: String
    public let signatureState: String
    public let state: String
    public let version: String
    public let sizeBytes: Int?
    public let supportedArchitectures: [Architecture]?
}

public extension Array where Element == DownloadableRuntime {
    func matchingArchitectures(_ architectures: [Architecture]) -> [DownloadableRuntime] {
        guard !architectures.isEmpty else { return self }
        return filter { $0.architectures?.containsAny(architectures) == true }
    }

    func matchingArchitectureFilters(_ filters: [ArchitectureFilter]) -> [DownloadableRuntime] {
        guard !filters.isEmpty else { return self }
        return filter { filters.matches($0.architectures) }
    }
}

extension InstalledRuntime {
    public enum Kind: String, Decodable, Sendable {
        case bundled = "Bundled with Xcode"
        case cryptexDiskImage = "Cryptex Disk Image"
        case diskImage = "Disk Image"
        case legacyDownload = "Legacy Download"
        case patchableCryptexDiskImage = "Patchable Cryptex Disk Image"
    }

    public enum Platform: String, Decodable, Sendable {
        case tvOS = "com.apple.platform.appletvsimulator"
        case iOS = "com.apple.platform.iphonesimulator"
        case watchOS = "com.apple.platform.watchsimulator"
        case visionOS = "com.apple.platform.xrsimulator"
        
        public var asPlatformOS: DownloadableRuntime.Platform {
            switch self {
                case .watchOS: return .watchOS
                case .iOS: return .iOS
                case .tvOS: return .tvOS
                case .visionOS: return .visionOS
            }
        }
    }
}
