import Foundation

public enum RuntimeArchiveInstallError: LocalizedError, Equatable, Sendable {
    case unsupportedContentType(DownloadableRuntime.ContentType, archiveURL: URL)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedContentType(contentType, archiveURL):
            return "Installing via \(contentType.rawValue) not support - please install manually from \(archiveURL.description)"
        }
    }
}

public struct RuntimeArchiveInstallService: Sendable {
    public typealias StepChanged = @Sendable (RuntimeInstallationStep) async -> Void

    private let installDiskImage: @Sendable (URL) async throws -> Void
    private let removeArchive: @Sendable (URL) throws -> Void

    public init(
        installDiskImage: @escaping @Sendable (URL) async throws -> Void,
        removeArchive: @escaping @Sendable (URL) throws -> Void
    ) {
        self.installDiskImage = installDiskImage
        self.removeArchive = removeArchive
    }

    public func install(
        runtime: DownloadableRuntime,
        archiveURL: URL,
        deleteArchive: Bool = true,
        stepChanged: StepChanged = { _ in }
    ) async throws {
        switch runtime.contentType {
        case .diskImage:
            await stepChanged(.installing)
            try await installDiskImage(archiveURL)
            try Task.checkCancellation()

            guard deleteArchive else { return }
            await stepChanged(.trashingArchive)
            try removeArchive(archiveURL)
        case .package, .cryptexDiskImage, .patchableCryptexDiskImage:
            throw RuntimeArchiveInstallError.unsupportedContentType(runtime.contentType, archiveURL: archiveURL)
        }
    }
}
