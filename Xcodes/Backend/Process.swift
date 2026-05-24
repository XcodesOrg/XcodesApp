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
