import Foundation

private typealias DownloadCompletionHandler = @Sendable (URL?, URLResponse?, Error?) -> Void

private final class DownloadTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(saveLocation: URL, response: URLResponse), Error>?

    func set(_ task: URLSessionDownloadTask) {
        lock.withLock {
            self.task = task
        }
    }

    func set(_ continuation: CheckedContinuation<(saveLocation: URL, response: URLResponse), Error>) {
        lock.withLock {
            self.continuation = continuation
        }
    }

    func resume(returning value: (saveLocation: URL, response: URLResponse)) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: error)
    }

    func cancel() {
        lock.withLock {
            task?.cancel()
        }
        resume(throwing: CancellationError())
    }
}

public extension URLSession {
    func downloadTaskAsync(
        with url: URL,
        to saveLocation: URL,
        resumingWith resumeData: Data?
    ) -> (progress: Progress, task: Task<(saveLocation: URL, response: URLResponse), Error>) {
        let taskBox = DownloadTaskBox()
        let completionHandler: DownloadCompletionHandler = { temporaryURL, response, error in
            if let error {
                taskBox.resume(throwing: error)
            } else if let response, let temporaryURL {
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: saveLocation)
                    taskBox.resume(returning: (saveLocation, response))
                } catch {
                    taskBox.resume(throwing: error)
                }
            } else {
                taskBox.resume(throwing: URLError(.unknown))
            }
        }
        let downloadTask: URLSessionDownloadTask
        if let resumeData {
            downloadTask = self.downloadTask(withResumeData: resumeData, completionHandler: completionHandler)
        } else {
            downloadTask = self.downloadTask(with: url, completionHandler: completionHandler)
        }
        taskBox.set(downloadTask)

        let operation = Task<(saveLocation: URL, response: URLResponse), Error> {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    taskBox.set(continuation)
                    if Task.isCancelled {
                        taskBox.cancel()
                    } else {
                        downloadTask.resume()
                    }
                }
            } onCancel: {
                taskBox.cancel()
            }
        }

        return (downloadTask.progress, operation)
    }
}
