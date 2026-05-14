import Foundation

/// Attempt and retry a task that fails with resume data up to `maximumRetryCount` times.
func attemptResumableTask<T: Sendable>(
    maximumRetryCount: Int = 3,
    delayBeforeRetry: TimeInterval = 2,
    _ body: @escaping (Data?) async throws -> T
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
                let nextResumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            else { throw error }

            resumeData = nextResumeData
            try await Task.sleep(nanoseconds: UInt64(delayBeforeRetry * 1_000_000_000))
        }
    }
}
