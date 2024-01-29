import Combine
import Foundation
import os.log
import Path
import XcodesKit

public typealias ProcessOutput = (status: Int32, out: String, err: String)

extension Process {
    @discardableResult
    static func run(_ executable: any Pathish, workingDirectory: URL? = nil, input: String? = nil, _ arguments: String...) -> AnyPublisher<ProcessOutput, Error> {
        return run(executable.url, workingDirectory: workingDirectory, input: input, arguments)
    }
    
    @discardableResult
    static func run(_ executable: URL, workingDirectory: URL? = nil, input: String? = nil, _ arguments: [String]) -> AnyPublisher<ProcessOutput, Error> {
        Deferred {
            Future<ProcessOutput, Error> { promise in
                DispatchQueue.global().async {
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
                            DispatchQueue.main.async {
                                promise(.failure(ProcessExecutionError(process: process, standardOutput: output, standardError: error)))
                            }
                            return
                        }
                        
                        DispatchQueue.main.async {
                            promise(.success((process.terminationStatus, output, error)))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            promise(.failure(error))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
