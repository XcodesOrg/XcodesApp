//
//  RuntimeInstallationStep.swift
//  
//
//  Created by Matt Kiazyk on 2023-11-23.
//

import Foundation

public enum RuntimeInstallationStep: Equatable, CustomStringConvertible {
    case downloading(progress: Progress)
    case installing
    case trashingArchive

    public var description: String {
        "(\(stepNumber)/\(stepCount)) \(message)"
    }

    public var message: String {
        switch self {
        case .downloading:
            return localizeString("Downloading")
        case .installing:
            return localizeString("Installing")
        case .trashingArchive:
            return localizeString("TrashingArchive")
        }
    }

    public var stepNumber: Int {
        switch self {
        case .downloading:      return 1
        case .installing:       return 2
        case .trashingArchive:  return 3
        }
    }

    public var stepCount: Int { 3 }
}
