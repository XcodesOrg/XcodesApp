import Foundation
import Path
import XcodesKit

public typealias ProcessOutput = XcodesKit.ProcessOutput
public typealias ProcessExecutionError = XcodesKit.ProcessExecutionError

extension Process {
    @discardableResult
    static func runAsync(_ executable: any Pathish, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await runAsync(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    @discardableResult
    static func runAsync(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        try await XcodesProcess.run(executable, workingDirectory: workingDirectory, input: input, arguments)
    }
}

extension XcodebuildRuntimeDownloadService {
    /// Runs with a per-process Xcode selection so a runtime can use an inactive Xcode.
    static func download(
        platform: String,
        buildVersion: String,
        architecture: String?,
        developerDirectory: String
    ) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var arguments = [
                    "DEVELOPER_DIR=\(developerDirectory)", "/usr/bin/xcodebuild",
                    "-downloadPlatform", platform, "-buildVersion", buildVersion
                ]
                if let architecture {
                    arguments += ["-architectureVariant", architecture]
                }

                do {
                    try Task.checkCancellation()
                    _ = try await XcodesProcess.run(URL(fileURLWithPath: "/usr/bin/env"), arguments)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension ProcessExecutionError {
    var runtimeFailureMessage: String {
        let diagnostics = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = String(format: localizeString("Xcode’s simulator runtime command failed (exit code %d)."), terminationStatus)
        if !diagnostics.isEmpty {
            return summary + "\n\n" + diagnostics
        }

        // Some Xcode versions report errors on stdout alongside carriage-return progress.
        let failure = standardOutput.split(whereSeparator: \.isNewline).last { line in
            line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed")
                || line.localizedCaseInsensitiveContains("cancelled")
        }
        return failure.map { summary + "\n\n" + $0 } ?? summary
    }
}
