//
//  Architecture.swift
//  XcodesKit
//
//  Created by Matt Kiazyk on 2025-08-23.
//

import Foundation

/// The name of an Architecture.
public enum Architecture: String, Codable, Equatable, Hashable, Identifiable, CaseIterable, Sendable {
    public var id: Self { self }
    
    /// The Arm64 architecture (Apple Silicon)
    case arm64 = "arm64"
    /// The X86\_64 architecture (64-bit Intel)
    case x86_64 = "x86_64"
    
    public var displayString: String {
        switch self {
        case .arm64:
            return localizeString("Apple Silicon")
        case .x86_64:
            return localizeString("Intel")
        }
    }
    
    public var iconName: String {
        switch self {
            case .arm64:
                return "m4.button.horizontal"
            case .x86_64:
                return "cpu.fill"
        }
    }
}

public enum ArchitectureVariant: String, Codable, Equatable, Hashable, Identifiable, CaseIterable, Sendable {
    public var id: Self { self }
    
    case universal
    case appleSilicon
    
    public var displayString: String {
        switch self {
        case .appleSilicon:
            return localizeString("Apple Silicon")
        case .universal:
            return localizeString("Universal")
        }
    }
    
    public var iconName: String {
        switch self {
            case .appleSilicon:
                return "m4.button.horizontal"
            case .universal:
                return "cpu.fill"
        }
    }
}

public enum ArchitectureFilter: Equatable, Hashable, Sendable {
    case architecture(Architecture)
    case variant(ArchitectureVariant)

    public init?(_ rawValue: String) {
        switch rawValue {
        case Architecture.arm64.rawValue:
            self = .architecture(.arm64)
        case Architecture.x86_64.rawValue:
            self = .architecture(.x86_64)
        case ArchitectureVariant.appleSilicon.rawValue, "apple-silicon", "apple_silicon":
            self = .variant(.appleSilicon)
        case ArchitectureVariant.universal.rawValue:
            self = .variant(.universal)
        default:
            return nil
        }
    }

    public func matches(_ architectures: [Architecture]?) -> Bool {
        guard let architectures, !architectures.isEmpty else { return false }

        switch self {
        case .architecture(let architecture):
            return architectures == [architecture]
        case .variant(.appleSilicon):
            return architectures.isAppleSilicon
        case .variant(.universal):
            return architectures.isUniversal
        }
    }
}

extension Array where Element == Architecture {
    public var isAppleSilicon: Bool {
        self == [.arm64]
    }
    
    public var isUniversal: Bool {
        self.contains([.arm64, .x86_64])
    }

    public func containsAny(_ architectures: [Architecture]) -> Bool {
        !Set(self).isDisjoint(with: architectures)
    }

    var listOutputSuffix: String {
        guard !isEmpty else { return "" }
        if isUniversal {
            return " [\(ArchitectureVariant.universal.displayString)]"
        }
        if isAppleSilicon {
            return " [\(ArchitectureVariant.appleSilicon.displayString)]"
        }
        return " [\(map(\.displayString).joined(separator: "|"))]"
    }
}

extension Array where Element == ArchitectureFilter {
    func matches(_ architectures: [Architecture]?) -> Bool {
        guard !isEmpty else { return true }
        return contains { $0.matches(architectures) }
    }
}
