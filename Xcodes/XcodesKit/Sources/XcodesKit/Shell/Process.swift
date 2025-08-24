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
                throw ProcessExecutionError(process: process, standardOutput: output, standardError: error)
            }
            
            return (process.terminationStatus, output, error)
        } catch {
            throw error
        }
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
