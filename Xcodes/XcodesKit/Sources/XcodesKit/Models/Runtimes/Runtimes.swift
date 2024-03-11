import Foundation

public struct DownloadableRuntimesResponse: Codable {
    public let sdkToSimulatorMappings: [SDKToSimulatorMapping]
    public let sdkToSeedMappings: [SDKToSeedMapping]
    public let refreshInterval: Int
    public let downloadables: [DownloadableRuntime]
    public let version: String
}

public struct DownloadableRuntime: Codable, Identifiable, Hashable {
    public let category: Category
    public let simulatorVersion: SimulatorVersion
    public let source: String
    public let dictionaryVersion: Int
    public let contentType: ContentType
    public let platform: Platform
    public let identifier: String
    public let version: String
    public let fileSize: Int
    public let hostRequirements: HostRequirements?
    public let name: String
    public let authentication: Authentication?
    public var url: URL {
        return URL(string: source)!
    }
    public var downloadPath: String {
        url.path
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
    }

    var betaNumber: Int? {
        enum Regex { static let shared = try! NSRegularExpression(pattern: "b[0-9]+$") }
        guard var foundString = Regex.shared.firstString(in: identifier) else { return nil }
        foundString.removeFirst()
        return Int(foundString)!
    }

    var completeVersion: String {
        makeVersion(for: simulatorVersion.version, betaNumber: betaNumber)
    }

    public var visibleIdentifier: String {
        return platform.shortName + " " + completeVersion
    }
    
    func makeVersion(for osVersion: String, betaNumber: Int?) -> String {
        let betaSuffix = betaNumber.flatMap { "-beta\($0)" } ?? ""
        return osVersion + betaSuffix
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

public struct SDKToSeedMapping: Codable {
    public let buildUpdate: String
    public let platform: DownloadableRuntime.Platform
    public let seedNumber: Int
}

public struct SDKToSimulatorMapping: Codable {
    public let sdkBuildUpdate: String
    public let simulatorBuildUpdate: String
    public let sdkIdentifier: String
}

extension DownloadableRuntime {
    public struct SimulatorVersion: Codable, Hashable {
        public let buildUpdate: String
        public let version: String
    }

    public struct HostRequirements: Codable, Hashable {
        let maxHostVersion: String?
        let excludedHostArchitectures: [String]?
        let minHostVersion: String?
        let minXcodeVersion: String?
    }

    public enum Authentication: String, Codable {
        case virtual = "virtual"
    }

    public enum Category: String, Codable {
        case simulator = "simulator"
    }

    public enum ContentType: String, Codable {
        case diskImage = "diskImage"
        case package = "package"
    }

    public enum Platform: String, Codable {
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

public struct InstalledRuntime: Decodable {
    let build: String
    let deletable: Bool
    let identifier: UUID
    let kind: Kind
    let lastUsedAt: Date?
    let path: String
    let platformIdentifier: Platform
    let runtimeBundlePath: String
    let runtimeIdentifier: String
    let signatureState: String
    let state: String
    let version: String
    let sizeBytes: Int?
}

extension InstalledRuntime {
    enum Kind: String, Decodable {
        case diskImage = "Disk Image"
        case bundled = "Bundled with Xcode"
        case legacyDownload = "Legacy Download"
    }

    enum Platform: String, Decodable {
        case tvOS = "com.apple.platform.appletvsimulator"
        case iOS = "com.apple.platform.iphonesimulator"
        case watchOS = "com.apple.platform.watchsimulator"
        case visionOS = "com.apple.platform.xrsimulator"
        
        var asPlatformOS: DownloadableRuntime.Platform {
            switch self {
                case .watchOS: return .watchOS
                case .iOS: return .iOS
                case .tvOS: return .tvOS
                case .visionOS: return .visionOS
            }
        }
    }
}

