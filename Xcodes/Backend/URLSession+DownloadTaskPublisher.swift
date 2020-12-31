import Combine
import Foundation

extension URLSession {
    /**
     - Parameter convertible: A URL or URLRequest.
     - Parameter saveLocation: A URL to move the downloaded file to after it completes. Apple deletes the temporary file immediately after the underyling completion handler returns.
     - Parameter resumeData: Data describing the state of a previously cancelled or failed download task. See the Discussion section for `downloadTask(withResumeData:completionHandler:)` https://developer.apple.com/documentation/foundation/urlsession/1411598-downloadtask#

     - Returns: Tuple containing a Progress object for the task and a publisher of the save location and response.

     - Note: We do not create the destination directory for you, because we move the file with FileManager.moveItem which changes its behavior depending on the directory status of the URL you provide. So create your own directory first!
     */
    public func downloadTask(
        with url: URL,
        to saveLocation: URL,
        resumingWith resumeData: Data?
    ) -> (progress: Progress, publisher: AnyPublisher<(saveLocation: URL, response: URLResponse), Error>) {
        var progress: Progress!
        var task: URLSessionDownloadTask!

        // Intentionally not wrapping in Deferred because we need to return the Progress and URLSessionDownloadTask immediately.
        // Probably a sign that this should be implemented differently...
        let promise = Future<(saveLocation: URL, response: URLResponse), Error> { promise in
            let completionHandler = { (temporaryURL: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    promise(.failure(error))
                } else if let response = response, let temporaryURL = temporaryURL {
                    do {
                        try FileManager.default.moveItem(at: temporaryURL, to: saveLocation)
                        promise(.success((saveLocation, response)))
                    } catch {
                        promise(.failure(error))
                    }
                } else {
                    fatalError("Expecting either a temporary URL and a response, or an error, but got neither.")
                }
            }

            if let resumeData = resumeData {
                task = self.downloadTask(withResumeData: resumeData, completionHandler: completionHandler)
            }
            else {
                task = self.downloadTask(with: url, completionHandler: completionHandler)
            }
            progress = task.progress
            task.resume()
        }
        .handleEvents(receiveCancel: task.cancel)
        .eraseToAnyPublisher()

        return (progress, promise)
    }
}
