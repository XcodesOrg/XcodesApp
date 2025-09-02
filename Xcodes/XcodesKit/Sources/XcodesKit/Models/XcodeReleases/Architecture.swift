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

extension Array where Element == Architecture {
    public var isAppleSilicon: Bool {
        self == [.arm64]
    }
}
