import Foundation

public struct XcodeInstallRetryService: Sendable {
    public typealias Attempt = @Sendable (Int) async throws -> InstalledXcode
    public typealias AttemptFailed = @Sendable (Error) async -> Void
    public typealias RetryDamagedArchive = @Sendable (Error, URL) async -> Void

    private let damagedArchiveURL: @Sendable (Error) -> URL?
    private let removeDamagedArchive: @Sendable (URL) throws -> Void

    public init(
        damagedArchiveURL: @escaping @Sendable (Error) -> URL?,
        removeDamagedArchive: @escaping @Sendable (URL) throws -> Void
    ) {
        self.damagedArchiveURL = damagedArchiveURL
        self.removeDamagedArchive = removeDamagedArchive
    }

    public func install(
        attemptNumber: Int = 0,
        shouldRetryAfterDamagedArchive: Bool = true,
        attempt: Attempt,
        onAttemptFailed: AttemptFailed = { _ in },
        onRetryDamagedArchive: RetryDamagedArchive = { _, _ in }
    ) async throws -> InstalledXcode {
        do {
            return try await attempt(attemptNumber)
        } catch {
            await onAttemptFailed(error)

            guard
                let damagedArchiveURL = damagedArchiveURL(error),
                attemptNumber < 1,
                shouldRetryAfterDamagedArchive
            else {
                throw error
            }

            await onRetryDamagedArchive(error, damagedArchiveURL)
            try removeDamagedArchive(damagedArchiveURL)
            return try await install(
                attemptNumber: attemptNumber + 1,
                shouldRetryAfterDamagedArchive: shouldRetryAfterDamagedArchive,
                attempt: attempt,
                onAttemptFailed: onAttemptFailed,
                onRetryDamagedArchive: onRetryDamagedArchive
            )
        }
    }
}
