import Foundation
import PromiseKit
import PMKFoundation

extension URLSession {
    /**
     - Parameter convertible: A URL or URLRequest.
     - Parameter saveLocation: A URL to move the downloaded file to after it completes. Apple deletes the temporary file immediately after the underyling completion handler returns.
     - Parameter resumeData: Data describing the state of a previously cancelled or failed download task. See the Discussion section for `downloadTask(withResumeData:completionHandler:)` https://developer.apple.com/documentation/foundation/urlsession/1411598-downloadtask#

     - Returns: Tuple containing a Progress object for the task and a promise containing the save location and response.

     - Note: We do not create the destination directory for you, because we move the file with FileManager.moveItem which changes its behavior depending on the directory status of the URL you provide. So create your own directory first!
     */
    public func downloadTask(with convertible: URLRequestConvertible, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        var progress: Progress!

        let promise = Promise<(saveLocation: URL, response: URLResponse)> { seal in
            let completionHandler = { (temporaryURL: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    seal.reject(error)
                } else if let response = response, let temporaryURL = temporaryURL {
                    do {
                        try FileManager.default.moveItem(at: temporaryURL, to: saveLocation)
                        seal.fulfill((saveLocation, response))
                    } catch {
                        seal.reject(error)
                    }
                } else {
                    seal.reject(PMKError.invalidCallingConvention)
                }
            }
            
            let task: URLSessionDownloadTask
            if let resumeData = resumeData {
                task = downloadTask(withResumeData: resumeData, completionHandler: completionHandler)
            }
            else {
                task = downloadTask(with: convertible.pmkRequest, completionHandler: completionHandler)
            }
            progress = task.progress
            task.resume()
        }

        return (progress, promise)
    }
}