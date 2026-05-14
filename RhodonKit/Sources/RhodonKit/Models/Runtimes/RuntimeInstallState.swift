//
//  RuntimeInstallState.swift
//
//
//  Created by Matt Kiazyk on 2023-11-23.
//

import Foundation
import Path

public enum RuntimeInstallState: Equatable, Hashable, @unchecked Sendable {
    case notInstalled
    case installing(RuntimeInstallationStep)
    case installed

    var notInstalled: Bool {
        switch self {
        case .notInstalled: true
        default: false
        }
    }

    var installing: Bool {
        switch self {
        case .installing: true
        default: false
        }
    }

    var installed: Bool {
        switch self {
        case .installed: true
        default: false
        }
    }
}
