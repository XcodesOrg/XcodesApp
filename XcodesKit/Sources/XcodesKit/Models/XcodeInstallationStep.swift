//
//  InstallationStep.swift
//  
//
//  Created by Matt Kiazyk on 2023-06-06.
//

import Foundation

// A numbered step
public enum XcodeInstallationStep: Equatable, CustomStringConvertible {
    case authenticating
    case downloading(progress: Progress)
    case unarchiving
    case moving(destination: String)
    case trashingArchive
    case checkingSecurity
    case finishing

    public var description: String {
        "(\(stepNumber)/\(stepCount)) \(message)"
    }

    public var message: String {
        switch self {
        case .authenticating:
            return localizeString("Authenticating")
        case .downloading:
            return localizeString("Downloading")
        case .unarchiving:
            return localizeString("Unarchiving")
        case .moving(let destination):
            return String(format: localizeString("Moving"), destination)
        case .trashingArchive:
            return localizeString("TrashingArchive")
        case .checkingSecurity:
            return localizeString("CheckingSecurity")
        case .finishing:
            return localizeString("Finishing")
        }
    }

    public var stepNumber: Int {
        switch self {
        case .authenticating:   return 1
        case .downloading:      return 2
        case .unarchiving:      return 3
        case .moving:           return 4
        case .trashingArchive:  return 5
        case .checkingSecurity: return 6
        case .finishing:        return 7
        }
    }

    public var stepCount: Int { 7 }
}

func localizeString(_ key: String, comment: String = "") -> String {
    if #available(macOS 12, *) {
        return String(localized: String.LocalizationValue(key))
    } else {
        return NSLocalizedString(key, comment: comment)
    }

}
