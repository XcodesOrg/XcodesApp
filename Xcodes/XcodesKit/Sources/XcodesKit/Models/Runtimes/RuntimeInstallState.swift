//
//  RuntimeInstallState.swift
//
//
//  Created by Matt Kiazyk on 2023-11-23.
//

import Foundation
import Path

public enum RuntimeInstallState: Equatable {
    case notInstalled
    case installing(RuntimeInstallationStep)
    case installed

    var notInstalled: Bool {
        switch self {
        case .notInstalled: return true
        default: return false
        }
    }
    var installing: Bool {
        switch self {
        case .installing: return true
        default: return false
        }
    }
    var installed: Bool {
        switch self {
        case .installed: return true
        default: return false
        }
    }
}
