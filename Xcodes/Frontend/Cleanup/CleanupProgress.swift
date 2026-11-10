import Foundation

/// Counts selected top-level operations; filesystem APIs do not report progress inside a folder.
struct CleanupProgress: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case trash, device, runtime

        var verb: String {
            switch self {
            case .trash: "Moving"
            case .device: "Deleting device"
            case .runtime: "Removing runtime"
            }
        }
    }

    let id = UUID()
    let totalCount: Int
    var completedCount = 0
    var movedCount = 0
    var deletedCount = 0
    var failureCount = 0
    var currentName: String?
    var currentPath: String?
    var action: Action = .trash
    var stopRequested = false
    var isFinished = false

    var statusText: String {
        if isFinished {
            if stopRequested && completedCount < totalCount { return "Stopped · \(completedCount) of \(totalCount) processed" }
            if failureCount > 0 { return "Cleanup finished · \(failureCount) failed" }
            if deletedCount == 0 { return "Moved \(movedCount) \(movedCount == 1 ? "item" : "items") to Trash" }
            let count = movedCount + deletedCount
            return "Cleaned up \(count) \(count == 1 ? "item" : "items")"
        }
        if stopRequested { return currentName == nil ? "Stopping cleanup…" : "Stopping after current item…" }
        guard currentName != nil else { return "Preparing cleanup…" }
        let count = "\(min(completedCount + 1, totalCount)) of \(totalCount)"
        return action == .trash ? "Moving \(count) to Trash…" : "\(action.verb) \(count)…"
    }
}
