//
//  Architecture.swift
//  XcodesKit
//
//  Created by Matt Kiazyk on 2025-08-23.
//

import Foundation

/// The name of an Architecture.
public enum Architecture: String, Codable, Equatable, Hashable {
    /// The Arm64 architecture (Apple Silicon)
    case arm64 = "arm64"
    /// The X86\_64 architecture (64-bit Intel)
    case x86_64 = "x86_64"
    /// The i386 architecture (32-bit Intel)
    case i386 = "i386"
    /// The PowerPC architecture (Motorola)
    case powerPC = "ppc"
}
