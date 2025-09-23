//
//  Architecture.swift
//  XcodesKit
//
//  Created by Matt Kiazyk on 2025-08-23.
//

import Foundation

/// The name of an Architecture.
public enum Architecture: String, Codable, Equatable, Hashable, Identifiable, CaseIterable {
    public var id: Self { self }
    
    /// The Arm64 architecture (Apple Silicon)
    case arm64 = "arm64"
    /// The X86\_64 architecture (64-bit Intel)
    case x86_64 = "x86_64"
    
    public var displayString: String {
        switch self {
        case .arm64:
            return "Apple Silicon"
        case .x86_64:
            return "Intel"
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

public enum ArchitectureVariant: String, Codable, Equatable, Hashable, Identifiable, CaseIterable {
    public var id: Self { self }
    
    case universal
    case appleSilicon
    
    public var displayString: String {
        switch self {
        case .appleSilicon:
            return "Apple Silicon"
        case .universal:
            return "Universal"
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

extension Array where Element == Architecture {
    public var isAppleSilicon: Bool {
        self == [.arm64]
    }
    
    public var isUniversal: Bool {
        self.contains([.arm64, .x86_64])
    }
}
