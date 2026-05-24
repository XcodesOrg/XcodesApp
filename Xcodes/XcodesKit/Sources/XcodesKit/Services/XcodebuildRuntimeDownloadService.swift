import Foundation
@preconcurrency import Path

public struct XcodebuildRuntimeDownloadService: Sendable {
    public init() {}

    public func download(
        platform: String,
        buildVersion: String,
        architecture: String? = nil
    ) -> AsyncThrowingStream<Progress, Error> {
        let progress = Progress()
        let process = Process()
        let xcodebuildPath = Path.root.usr.bin.join("xcodebuild").url

        process.executableURL = xcodebuildPath
        process.arguments = [
            "-downloadPlatform",
            platform,
            "-buildVersion",
            buildVersion
        ]

        if let architecture {
            process.arguments?.append(contentsOf: [
                "-architectureVariant",
                architecture
            ])
        }

        return ProcessProgressStreamRunner(
            process: process,
            progress: progress,
            outputHandler: { string, progress in
                progress.updateFromXcodebuild(text: string)
            },
            failureHandler: { process in
                ProcessExecutionError(process: process, standardOutput: "", standardError: "")
            }
        ).stream()
    }
}
