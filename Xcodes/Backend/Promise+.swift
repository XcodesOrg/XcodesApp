import Foundation
import PromiseKit

/// Attempt and retry a task that fails with resume data up to `maximumRetryCount` times
func attemptResumableTask<T>(
    maximumRetryCount: Int = 3,
    delayBeforeRetry: DispatchTimeInterval = .seconds(2),
    _ body: @escaping (Data?) -> Promise<T>
) -> Promise<T> {
    var attempts = 0
    func attempt(with resumeData: Data? = nil) -> Promise<T> {
        attempts += 1
        return body(resumeData).recover { error -> Promise<T> in
            guard
                attempts < maximumRetryCount,
                let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            else { throw error }

            return after(delayBeforeRetry).then(on: nil) { attempt(with: resumeData) }
        }
    }
    return attempt()
}

/// Attempt and retry a task up to `maximumRetryCount` times
func attemptRetryableTask<T>(
    maximumRetryCount: Int = 3,
    delayBeforeRetry: DispatchTimeInterval = .seconds(2),
    _ body: @escaping () -> Promise<T>
) -> Promise<T> {
    var attempts = 0
    func attempt() -> Promise<T> {
        attempts += 1
        return body().recover { error -> Promise<T> in
            guard attempts < maximumRetryCount else { throw error }
            return after(delayBeforeRetry).then(on: nil) { attempt() }
        }
    }
    return attempt()
}
