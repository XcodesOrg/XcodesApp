//
//  RuntimeInstallationStep.swift
//
//
//  Created by Matt Kiazyk on 2023-11-23.
//

import Foundation

public enum RuntimeInstallationStep: Equatable, CustomStringConvertible, Hashable, @unchecked Sendable {
    case downloading(progress: Progress)
    case installing
    case trashingArchive

    public var description: String {
        "(\(stepNumber)/\(stepCount)) \(message)"
    }

    public var message: String {
        switch self {
        case .downloading:
            "Downloading"
        case .installing:
            "Installing"
        case .trashingArchive:
            "Moving archive to the Trash"
        }
    }

    public var stepNumber: Int {
        switch self {
        case .downloading: 1
        case .installing: 2
        case .trashingArchive: 3
        }
    }

    public var stepCount: Int {
        3
    }
}
