import Combine
import Foundation
import os.log
import Path
import XcodesKit

public struct ProcessOutput: Sendable {
    let status: Int32
    let out: String
    let err: String
}

private final class PromiseBox<Output>: @unchecked Sendable {
    nonisolated(unsafe) let promise: (Result<Output, Error>) -> Void

    nonisolated init(_ promise: @escaping (Result<Output, Error>) -> Void) {
        self.promise = promise
    }

    nonisolated func resolve(_ result: Result<Output, Error>) {
        promise(result)
    }
}

private struct ProcessConfiguration {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe
}

extension Process {
    @discardableResult
    static func run(
        _ executable: any Pathish,
        workingDirectory: URL? = nil,
        input: String? = nil,
        _ arguments: String...
    ) -> AnyPublisher<ProcessOutput, Error> {
        run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }

    @discardableResult
    static func run(
        _ executable: URL,
        workingDirectory: URL? = nil,
        input: String? = nil,
        _ arguments: [String]
    ) -> AnyPublisher<ProcessOutput, Error> {
        Deferred {
            Future<ProcessOutput, Error> { promise in
                let promiseBox = PromiseBox(promise)

                DispatchQueue.global().async {
                    do {
                        let processOutput = try executeProcess(
                            executable: executable,
                            workingDirectory: workingDirectory,
                            input: input,
                            arguments: arguments
                        )
                        DispatchQueue.main.async {
                            promiseBox.resolve(.success(processOutput))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            promiseBox.resolve(.failure(error))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    private static func executeProcess(
        executable: URL,
        workingDirectory: URL?,
        input: String?,
        arguments: [String]
    ) throws -> ProcessOutput {
        let processConfiguration = configuredProcess(
            executable: executable,
            workingDirectory: workingDirectory,
            input: input,
            arguments: arguments
        )
        let process = processConfiguration.process

        Logger.subprocess
            .info(
                // swiftlint:disable:next line_length
                "Process.run executable: \(executable), input: \(input ?? ""), arguments: \(arguments.joined(separator: ", "))"
            )

        try process.run()
        process.waitUntilExit()

        let output = readString(from: processConfiguration.stdout)
        let error = readString(from: processConfiguration.stderr)

        Logger.subprocess.info("Process.run output: \(output)")
        if !error.isEmpty {
            Logger.subprocess.error("Process.run error: \(error)")
        }

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ProcessExecutionError(process: process, standardOutput: output, standardError: error)
        }

        return ProcessOutput(status: process.terminationStatus, out: output, err: error)
    }

    private static func configuredProcess(
        executable: URL,
        workingDirectory: URL?,
        input: String?,
        arguments: [String]
    ) -> ProcessConfiguration {
        let process = Process()
        process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if let input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe.fileHandleForReading
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }

        return ProcessConfiguration(process: process, stdout: stdout, stderr: stderr)
    }

    private static func readString(from pipe: Pipe) -> String {
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
