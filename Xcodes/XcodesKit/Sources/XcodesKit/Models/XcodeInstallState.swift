//
//  InstallState.swift
//  
//
//  Created by Matt Kiazyk on 2023-06-06.
//

import Foundation
@preconcurrency import Path

public enum XcodeInstallState: Equatable, Sendable {
    case notInstalled
    case installing(XcodeInstallationStep)
    case installed(Path)

    public var notInstalled: Bool {
        switch self {
        case .notInstalled: return true
        default: return false
        }
    }
    public var installing: Bool {
        switch self {
        case .installing: return true
        default: return false
        }
    }
    public var installed: Bool {
        switch self {
        case .installed: return true
        default: return false
        }
    }

    public var installedPath: Path? {
        switch self {
        case .installed(let path): return path
        default: return nil
        }
    }
}
