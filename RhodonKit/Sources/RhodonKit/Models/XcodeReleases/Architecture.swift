//
//  Architecture.swift
//  RhodonKit
//
//  Created by Matt Kiazyk on 2025-08-23.
//

import Foundation

/// The name of an Architecture.
public enum Architecture: String, Codable, Equatable, Hashable, Identifiable, CaseIterable, Sendable {
    public var id: Self {
        self
    }

    /// The Arm64 architecture (Apple Silicon)
    case arm64
    /// The X86\_64 architecture (64-bit Intel)
    case x8664 = "x86_64"

    public var displayString: String {
        switch self {
        case .arm64:
            "Apple Silicon"
        case .x8664:
            "Intel"
        }
    }

    public var iconName: String {
        switch self {
        case .arm64:
            "m4.button.horizontal"
        case .x8664:
            "cpu.fill"
        }
    }
}

public enum ArchitectureVariant: String, Codable, Equatable, Hashable, Identifiable, CaseIterable, Sendable {
    public var id: Self {
        self
    }

    case universal
    case appleSilicon

    public var displayString: String {
        switch self {
        case .appleSilicon:
            "Apple Silicon"
        case .universal:
            "Universal"
        }
    }

    public var iconName: String {
        switch self {
        case .appleSilicon:
            "m4.button.horizontal"
        case .universal:
            "cpu.fill"
        }
    }
}

public extension [Architecture] {
    var isAppleSilicon: Bool {
        self == [.arm64]
    }

    var isUniversal: Bool {
        contains([.arm64, .x8664])
    }
}
