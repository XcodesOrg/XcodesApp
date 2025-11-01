import Foundation
import Path
import os.log

public typealias ProcessOutput = (status: Int32, out: String, err: String)

extension Process {
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) async throws -> ProcessOutput {
        return try run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    static func run(_ executable: Path, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) throws -> ProcessOutput {
        return try run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        process.currentDirectoryURL = workingDirectory ?? executable.deletingLastPathComponent()
        process.executableURL = executable
        process.arguments = arguments
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        var output = Data()
        var error = Data()

        let outputLock = NSLock()
        let errorLock = NSLock()
        
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputLock.lock()
                output.append(data)
                outputLock.unlock()
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorLock.lock()
                error.append(data)
                errorLock.unlock()
            }
        }

        if let input = input {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            if let inputData = input.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
            }
            inputPipe.fileHandleForWriting.closeFile()
        }

        do {
            Logger.subprocess.info("Process.run executable: \(executable), input: \(input ?? ""), arguments: \(arguments.joined(separator: ", "))")
            try process.run()
            process.waitUntilExit()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        outputLock.lock()
        let outputString = String(data: output, encoding: .utf8) ?? ""
        outputLock.unlock()
        errorLock.lock()
        let errorString = String(data: error, encoding: .utf8) ?? ""
        errorLock.unlock()

        Logger.subprocess.info("Process.run output: \(outputString)")
        if !errorString.isEmpty {
            Logger.subprocess.error("Process.run error: \(errorString)")
        }

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ProcessExecutionError(process: process, standardOutput: outputString, standardError: errorString)
        }

        return (process.terminationStatus, outputString, errorString)
    }
    
}

public struct ProcessExecutionError: Error {
    public let process: Process
    public let standardOutput: String
    public let standardError: String
    
    public init(process: Process, standardOutput: String, standardError: String) {
        self.process = process
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
