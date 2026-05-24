import Foundation

public enum XcodeUnarchiveError: Error, Equatable, Sendable {
    case damagedXIP(url: URL)
    case notEnoughFreeSpaceToExpandArchive(url: URL)
}

public enum XcodeUnarchiveStep: Equatable, Sendable {
    case unarchiving
    case moving(destination: String)
}

public struct XcodeUnarchiveService: Sendable {
    public typealias Unarchive = @Sendable (URL) async throws -> Void
    public typealias FileExists = @Sendable (String) -> Bool
    public typealias MoveItem = @Sendable (URL, URL) throws -> Void
    public typealias RemoveItem = @Sendable (URL) throws -> Void
    public typealias StepChanged = @Sendable (XcodeUnarchiveStep) async -> Void

    private let unarchive: Unarchive
    private let fileExists: FileExists
    private let moveItem: MoveItem
    private let removeItem: RemoveItem

    public init(
        unarchive: @escaping Unarchive,
        fileExists: @escaping FileExists,
        moveItem: @escaping MoveItem,
        removeItem: @escaping RemoveItem
    ) {
        self.unarchive = unarchive
        self.fileExists = fileExists
        self.moveItem = moveItem
        self.removeItem = removeItem
    }

    public func unarchiveAndMoveXIP(
        at source: URL,
        to destination: URL,
        stepChanged: @escaping StepChanged = { _ in }
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try await unarchiveAndMoveXIPWithoutCancellationHandler(
                at: source,
                to: destination,
                stepChanged: stepChanged
            )
        } onCancel: {
            if fileExists(source.path) {
                try? removeItem(source)
            }
            if fileExists(destination.path) {
                try? removeItem(destination)
            }
        }
    }

    private func unarchiveAndMoveXIPWithoutCancellationHandler(
        at source: URL,
        to destination: URL,
        stepChanged: StepChanged
    ) async throws -> URL {
        await stepChanged(.unarchiving)

        do {
            try await unarchive(source)
        } catch {
            if let executionError = error as? ProcessExecutionError {
                if executionError.standardError.contains("damaged and can’t be expanded") {
                    throw XcodeUnarchiveError.damagedXIP(url: source)
                }
                if executionError.standardError.contains("can’t be expanded because the selected volume doesn’t have enough free space.") {
                    throw XcodeUnarchiveError.notEnoughFreeSpaceToExpandArchive(url: source)
                }
            }
            throw error
        }

        await stepChanged(.moving(destination: destination.path))

        let xcodeURL = source.deletingLastPathComponent().appendingPathComponent("Xcode.app")
        let xcodeBetaURL = source.deletingLastPathComponent().appendingPathComponent("Xcode-beta.app")
        if fileExists(xcodeURL.path) {
            try moveItem(xcodeURL, destination)
        } else if fileExists(xcodeBetaURL.path) {
            try moveItem(xcodeBetaURL, destination)
        }

        return destination
    }
}
