import Foundation
import os
@preconcurrency import Path

public struct Aria2DownloadService: Sendable {
    public init() {}

    public func download(
        aria2Path: Path,
        url: URL,
        destination: Path,
        cookies: [HTTPCookie],
        progress: Progress = Progress(),
        unauthorizedError: (@Sendable () -> Error)? = nil
    ) -> AsyncThrowingStream<Progress, Error> {
        let process = Process()
        process.executableURL = aria2Path.url
        process.arguments = [
            "--header=Cookie: \(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))",
            "--max-connection-per-server=16",
            "--split=16",
            "--summary-interval=1",
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
            "--dir=\(destination.parent.string)",
            "--out=\(destination.basename())",
            "--human-readable=false",
            url.absoluteString,
        ]

        let state = UnauthorizedState()
        let runner = ProcessProgressStreamRunner(
            process: process,
            progress: progress,
            outputHandler: { string, progress in
                if string.contains("Redirecting to https://developer.apple.com/unauthorized/") {
                    state.markUnauthorized()
                }

                progress.updateFromAria2(string: string)
            },
            failureHandler: { process in
                if let aria2cError = Aria2CError(exitStatus: process.terminationStatus) {
                    return aria2cError
                } else {
                    return ProcessExecutionError(process: process, standardOutput: "", standardError: "")
                }
            },
            successHandler: {
                guard !state.isUnauthorized else {
                    return unauthorizedError?() ?? XcodesKitError("Received 403: Unauthorized.")
                }
                return nil
            }
        )

        return runner.stream()
    }
}

private final class UnauthorizedState: Sendable {
    private let unauthorized = OSAllocatedUnfairLock(initialState: false)

    var isUnauthorized: Bool {
        unauthorized.withLock { $0 }
    }

    func markUnauthorized() {
        unauthorized.withLock { $0 = true }
    }
}
