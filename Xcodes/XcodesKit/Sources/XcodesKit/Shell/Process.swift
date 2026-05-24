import Foundation
@preconcurrency import Path
import os
import os.log

public typealias ProcessOutput = (status: Int32, out: String, err: String)

public enum XcodesProcess: Sendable {
    public static func sudo<P: Pathish>(password: String? = nil, _ executable: P, workingDirectory: URL? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await sudo(password: password, executable, workingDirectory: workingDirectory, arguments)
    }

    public static func sudo<P: Pathish>(password: String? = nil, _ executable: P, workingDirectory: URL? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        var arguments = [executable.string] + arguments
        if password != nil {
            arguments.insert("-S", at: 0)
        }
        return try await run(Path.root.usr.bin.sudo.url, workingDirectory: workingDirectory, input: password, arguments)
    }

    public static func run<P: Pathish>(_ executable: P, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await run(executable, workingDirectory: workingDirectory, input: input, arguments)
    }

    public static func run<P: Pathish>(_ executable: P, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        try await run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }

    public static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await Process.run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }

    public static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        try await Process.run(executable, workingDirectory: workingDirectory, input: input, arguments)
    }
}

public extension Process {
    @discardableResult
    static func sudoAsync<P: Pathish>(password: String? = nil, _ executable: P, workingDirectory: URL? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await XcodesProcess.sudo(password: password, executable, workingDirectory: workingDirectory, arguments)
    }

    @discardableResult
    static func runAsync<P: Pathish>(_ executable: P, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        try await XcodesProcess.run(executable, workingDirectory: workingDirectory, input: input, arguments)
    }

    @discardableResult
    static func runAsync(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        try await XcodesProcess.run(executable, workingDirectory: workingDirectory, input: input, arguments)
    }
}

extension Process {
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        return try await run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) throws -> ProcessOutput {
        return try run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) throws -> ProcessOutput {
        
        let process = Process()
        process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments
        
        let (stdout, stderr) = (Pipe(), Pipe())
        process.standardOutput = stdout
        process.standardError = stderr
        
        if let input = input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe.fileHandleForReading
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }
        
        do {
            Logger.subprocess.info("Process.run executable: \(executable), input: \(input ?? ""), arguments: \(arguments.joined(separator: ", "))")

            try process.run()
            process.waitUntilExit()
            
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            Logger.subprocess.info("Process.run output: \(output)")
            if !error.isEmpty {
                Logger.subprocess.error("Process.run error: \(error)")
            }

            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw ProcessExecutionError(process: process, terminationStatus: process.terminationStatus, standardOutput: output, standardError: error)
            }
            
            return (process.terminationStatus, output, error)
        } catch {
            throw error
        }
    }

    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) async throws -> ProcessOutput {
        let process = Process()
        process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments

        let (stdout, stderr) = (Pipe(), Pipe())
        process.standardOutput = stdout
        process.standardError = stderr

        if let input = input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe.fileHandleForReading
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }

        Logger.subprocess.info("Process.run executable: \(executable), input: \(input ?? ""), arguments: \(arguments.joined(separator: ", "))")

        let runner = AsyncProcessRunner(process: process, stdout: stdout, stderr: stderr)
        return try await withTaskCancellationHandler {
            try await runner.run()
        } onCancel: {
            runner.cancel()
        }
    }
    
}

private final class AsyncProcessRunner: Sendable {
    private let process: Process
    private let stdout: Pipe
    private let stderr: Pipe
    private let request = OneShotContinuation<ProcessOutput>()
    private let output = OSAllocatedUnfairLock(initialState: OutputStorage())

    init(process: Process, stdout: Pipe, stderr: Pipe) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
    }

    func run() async throws -> ProcessOutput {
        try await request.value {
            startReadingOutput()

            process.terminationHandler = { [weak self] process in
                self?.finish(process: process)
            }

            do {
                try process.run()
            } catch {
                clearReadabilityHandlers()
                throw error
            }
        }
    }

    func cancel() {
        if process.isRunning {
            process.terminate()
        }
        clearReadabilityHandlers()
        request.resume(throwing: CancellationError())
    }

    private func finish(process: Process) {
        clearReadabilityHandlers()
        appendRemainingOutput()

        let data = output.withLock { $0 }
        let output = string(from: data.stdout)
        let error = string(from: data.stderr)

        Logger.subprocess.info("Process.run output: \(output)")
        if !error.isEmpty {
            Logger.subprocess.error("Process.run error: \(error)")
        }

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            resume(throwing: ProcessExecutionError(process: process, terminationStatus: process.terminationStatus, standardOutput: output, standardError: error))
            return
        }

        resume(returning: (process.terminationStatus, output, error))
    }

    private func resume(returning output: ProcessOutput) {
        request.resume(with: .success(output))
    }

    private func resume(throwing error: Swift.Error) {
        request.resume(throwing: error)
    }

    private func startReadingOutput() {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendAvailableData(from: handle, stream: .stdout)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendAvailableData(from: handle, stream: .stderr)
        }
    }

    private func appendAvailableData(from handle: FileHandle, stream: OutputStream) {
        let data = handle.availableData
        guard data.isEmpty == false else { return }

        output.withLock {
            append(data, to: stream, storage: &$0)
        }
    }

    private func appendRemainingOutput() {
        let remainingStdout = stdout.fileHandleForReading.readDataToEndOfFile()
        let remainingStderr = stderr.fileHandleForReading.readDataToEndOfFile()

        output.withLock {
            append(remainingStdout, to: .stdout, storage: &$0)
            append(remainingStderr, to: .stderr, storage: &$0)
        }
    }

    private func append(_ data: Data, to stream: OutputStream, storage: inout OutputStorage) {
        guard data.isEmpty == false else { return }

        switch stream {
        case .stdout:
            storage.stdout.append(data)
        case .stderr:
            storage.stderr.append(data)
        }
    }

    private func clearReadabilityHandlers() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
    }

    private func string(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    private enum OutputStream {
        case stdout
        case stderr
    }

    private struct OutputStorage: Sendable {
        var stdout = Data()
        var stderr = Data()
    }
}

public struct ProcessExecutionError: Error, Sendable {
    public let processDescription: String
    public let terminationStatus: Int32
    public let standardOutput: String
    public let standardError: String
    
    public init(process: Process, terminationStatus: Int32 = 0, standardOutput: String?, standardError: String?) {
        self.processDescription = process.description
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput ?? ""
        self.standardError = standardError ?? ""
    }
}
