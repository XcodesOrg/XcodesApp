import Foundation
import os

extension URLSession {
    /**
     - Parameter request: The URL request to download.
     - Parameter saveLocation: A URL to move the downloaded file to after it completes. Apple deletes the temporary file immediately after the underlying completion handler returns.
     - Parameter resumeData: Data describing the state of a previously cancelled or failed download task. See the Discussion section for `downloadTask(withResumeData:completionHandler:)` https://developer.apple.com/documentation/foundation/urlsession/1411598-downloadtask#

     - Returns: Tuple containing a Progress object for the task and a task containing the save location and response.

     - Note: We do not create the destination directory for you, because we move the file with FileManager.moveItem which changes its behavior depending on the directory status of the URL you provide. So create your own directory first.
     */
    public func downloadTask(
        with request: URLRequest,
        to saveLocation: URL,
        resumingWith resumeData: Data?
    ) -> (progress: Progress, task: Task<(saveLocation: URL, response: URLResponse), Error>) {
        let runner = URLSessionDownloadTaskRunner(
            session: self,
            request: request,
            saveLocation: saveLocation,
            resumeData: resumeData
        )
        let task = Task {
            try await runner.resume()
        }
        return (runner.progress, task)
    }

    public func downloadTaskAsync(
        with url: URL,
        to saveLocation: URL,
        resumingWith resumeData: Data?
    ) -> (progress: Progress, task: Task<(saveLocation: URL, response: URLResponse), Error>) {
        downloadTask(with: URLRequest(url: url), to: saveLocation, resumingWith: resumeData)
    }
}

private final class URLSessionDownloadTaskRunner: Sendable {
    let progress: Progress

    private let task: URLSessionDownloadTask
    private let saveLocation: URL
    private let request = OneShotContinuation<(temporaryURL: URL, response: URLResponse)>()

    init(session: URLSession, request: URLRequest, saveLocation: URL, resumeData: Data?) {
        self.saveLocation = saveLocation

        let callbackBox = URLSessionDownloadTaskCallbackBox()
        let createdTask: URLSessionDownloadTask
        if let resumeData {
            createdTask = session.downloadTask(withResumeData: resumeData) { temporaryURL, response, error in
                callbackBox.complete(temporaryURL: temporaryURL, response: response, error: error)
            }
        } else {
            createdTask = session.downloadTask(with: request) { temporaryURL, response, error in
                callbackBox.complete(temporaryURL: temporaryURL, response: response, error: error)
            }
        }

        self.task = createdTask
        self.progress = createdTask.progress
        callbackBox.handler = { [weak self] temporaryURL, response, error in
            self?.complete(temporaryURL: temporaryURL, response: response, error: error)
        }
    }

    func resume() async throws -> (saveLocation: URL, response: URLResponse) {
        let output = try await request.value(onCancel: { [task] in
            task.cancel()
        }) {
            task.resume()
        }
        try FileManager.default.moveItem(at: output.temporaryURL, to: saveLocation)
        return (saveLocation, output.response)
    }

    private func complete(temporaryURL: URL?, response: URLResponse?, error: Error?) {
        let result: Result<(temporaryURL: URL, response: URLResponse), Error>
        if let error {
            result = .failure(error)
        } else if let temporaryURL, let response {
            result = .success((temporaryURL, response))
        } else {
            result = .failure(URLError(.badServerResponse))
        }

        finish(result)
    }

    private func finish(_ result: Result<(temporaryURL: URL, response: URLResponse), Error>) {
        request.resume(with: result)
    }
}

private final class URLSessionDownloadTaskCallbackBox: Sendable {
    typealias Handler = @Sendable (URL?, URLResponse?, Error?) -> Void

    private let storedHandler = OSAllocatedUnfairLock<Handler?>(initialState: nil)

    var handler: Handler? {
        get {
            storedHandler.withLock { $0 }
        }
        set {
            storedHandler.withLock { $0 = newValue }
        }
    }

    func complete(temporaryURL: URL?, response: URLResponse?, error: Error?) {
        handler?(temporaryURL, response, error)
    }
}
