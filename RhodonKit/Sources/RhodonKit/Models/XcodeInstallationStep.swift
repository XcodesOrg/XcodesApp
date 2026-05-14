//
//  XcodeInstallationStep.swift
//
//
//  Created by Matt Kiazyk on 2023-06-06.
//

import Foundation

/// A numbered step
public enum XcodeInstallationStep: Equatable, CustomStringConvertible, @unchecked Sendable {
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
            "Authenticating"
        case .downloading:
            "Downloading"
        case .unarchiving:
            "Unarchiving (This can take a while)"
        case let .moving(destination):
            "Moving to \(destination)"
        case .trashingArchive:
            "Moving archive to the Trash"
        case .checkingSecurity:
            "Security verification"
        case .finishing:
            "Finishing"
        }
    }

    public var stepNumber: Int {
        switch self {
        case .authenticating: 1
        case .downloading: 2
        case .unarchiving: 3
        case .moving: 4
        case .trashingArchive: 5
        case .checkingSecurity: 6
        case .finishing: 7
        }
    }

    public var stepCount: Int {
        7
    }
}
