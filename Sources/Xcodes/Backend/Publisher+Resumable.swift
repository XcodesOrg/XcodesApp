import Combine
import Foundation

/// Attempt and retry a task that fails with resume data up to `maximumRetryCount` times
func attemptResumableTask<T>(
    maximumRetryCount: Int = 3,
    delayBeforeRetry: TimeInterval = 2,
    _ body: @escaping (Data?) -> AnyPublisher<T, Error>
) -> AnyPublisher<T, Error> {
    var attempts = 0
    func attempt(with resumeData: Data? = nil) -> AnyPublisher<T, Error> {
        attempts += 1
        return body(resumeData)
            .catch { error -> AnyPublisher<T, Error> in
                guard
                    attempts < maximumRetryCount,
                    let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                else { return Fail(error: error).eraseToAnyPublisher() }
                
                return attempt(with: resumeData)
                    .delay(for: .seconds(delayBeforeRetry), scheduler: DispatchQueue.main)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    return attempt()
}

///// Attempt and retry a task up to `maximumRetryCount` times
//func attemptRetryableTask<T>(
//    maximumRetryCount: Int = 3,
//    delayBeforeRetry: DispatchTimeInterval = .seconds(2),
//    _ body: @escaping () -> AnyPublisher<T, Error>
//) -> AnyPublisher<T, Error> {
//    var attempts = 0
//    func attempt() -> Promise<T> {
//        attempts += 1
//        return body().recover { error -> Promise<T> in
//            guard attempts < maximumRetryCount else { throw error }
//            return after(delayBeforeRetry).then(on: nil) { attempt() }
//        }
//    }
//    return attempt()
//}
