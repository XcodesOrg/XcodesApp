import Foundation

/// A numbered step
enum InstallationStep: Equatable, CustomStringConvertible {
    case downloading(progress: Progress)
    case unarchiving
    case moving(destination: String)
    case trashingArchive
    case checkingSecurity
    case finishing

    var description: String {
        "(\(stepNumber)/\(stepCount)) \(message)"
    }

    var message: String {
        switch self {
        case .downloading:
            return "Downloading"
        case .unarchiving:
            return "Unarchiving (This can take a while)"
        case .moving(let destination):
            return "Moving to \(destination)"
        case .trashingArchive:
            return "Moving archive to the Trash"
        case .checkingSecurity:
            return "Security verification"
        case .finishing:
            return "Finishing"
        }
    }

    var stepNumber: Int {
        switch self {
        case .downloading:      return 1
        case .unarchiving:      return 2
        case .moving:           return 3
        case .trashingArchive:  return 4
        case .checkingSecurity: return 5
        case .finishing:        return 6
        }
    }

    var stepCount: Int { 6 }
}
