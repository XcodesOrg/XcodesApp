import Foundation
import os
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
        developerDirectory: String?
    ) -> AsyncThrowingStream<Progress, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        if let developerDirectory {
            process.environment = ProcessInfo.processInfo.environment.merging(["DEVELOPER_DIR": developerDirectory]) { _, scoped in scoped }
        }
        process.arguments = ["-downloadPlatform", platform, "-buildVersion", buildVersion]
        if let architecture {
            process.arguments?.append(contentsOf: ["-architectureVariant", architecture])
        }
        return runtimeProgressStream(for: process)
    }

    static func runtimeProgressStream(for process: Process) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let output = OSAllocatedUnfairLock(initialState: RuntimeCommandOutput())
            let progress = Progress(totalUnitCount: 100)
            progress.kind = .file
            progress.fileOperationKind = .downloading
            continuation.yield(progress)

            // Wait for exit and both pipes to drain so the final diagnostic is available.
            let finish: @Sendable () -> Void = {
                let result = output.withLock { $0.completedOutput() }
                guard let result else { return }
                if process.terminationReason == .exit, process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ProcessExecutionError(
                        process: process, terminationStatus: process.terminationStatus,
                        standardOutput: result.stdout, standardError: result.stderr
                    ))
                }
            }

            for (pipe, isError) in [(stdout, false), (stderr, true)] {
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { handle.readabilityHandler = nil }
                    output.withLock {
                        if data.isEmpty {
                            $0.closedPipes += 1
                        } else if isError {
                            $0.stderr.append(data)
                        } else {
                            $0.stdout.append(data)
                            $0.progressBuffer.append(data)
                            if let lastDelimiter = $0.progressBuffer.lastIndex(where: { $0 == 10 || $0 == 13 }) {
                                let records = String(decoding: $0.progressBuffer[...lastDelimiter], as: UTF8.self)
                                $0.progressBuffer.removeSubrange(...lastDelimiter)
                                for record in records.split(whereSeparator: \.isNewline) {
                                    let line = record.trimmingCharacters(in: .whitespaces)
                                    if line.hasPrefix("Installing") {
                                        if !$0.installing {
                                            $0.installing = true
                                            continuation.yield(Progress(totalUnitCount: -1))
                                        }
                                    } else if !$0.installing, line.contains("%") {
                                        progress.updateFromXcodebuild(text: line)
                                        continuation.yield(progress)
                                    }
                                }
                            }
                        }
                    }
                    if data.isEmpty { finish() }
                }
            }

            process.terminationHandler = { process in
                process.terminationHandler = nil
                output.withLock { $0.exited = true }
                finish()
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason, process.isRunning { process.terminate() }
            }
            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct RuntimeCommandOutput {
    var stdout = Data()
    var stderr = Data()
    var progressBuffer = Data()
    var installing = false
    var closedPipes = 0
    var exited = false
    var finished = false

    mutating func completedOutput() -> (stdout: String, stderr: String)? {
        guard exited, closedPipes == 2, !finished else { return nil }
        finished = true
        return (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
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
