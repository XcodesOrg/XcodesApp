import Foundation

/// Attempts a resumable async task and retries failures that include URLSession resume data.
public func attemptResumableTask<T>(
    maximumRetryCount: Int = 3,
    delayBeforeRetry: Duration = .seconds(2),
    shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
    _ body: @escaping @Sendable (Data?) async throws -> T
) async throws -> T {
    var attempts = 0
    var resumeData: Data?

    while true {
        attempts += 1

        do {
            return try await body(resumeData)
        } catch {
            guard
                attempts < maximumRetryCount,
                shouldRetry(error),
                let nextResumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            else {
                throw error
            }

            resumeData = nextResumeData
            try await Task.sleep(for: delayBeforeRetry)
        }
    }
}

/// Attempts an async task and retries caller-approved failures.
public func attemptRetryableTask<T>(
    maximumRetryCount: Int = 3,
    delayBeforeRetry: Duration = .seconds(2),
    shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    var attempts = 0

    while true {
        attempts += 1

        do {
            return try await body()
        } catch {
            guard attempts < maximumRetryCount, shouldRetry(error) else {
                throw error
            }

            try await Task.sleep(for: delayBeforeRetry)
        }
    }
}
