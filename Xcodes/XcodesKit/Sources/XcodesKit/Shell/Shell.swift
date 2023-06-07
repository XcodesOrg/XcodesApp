import Foundation
import Path

public struct Shell {
    public var installedRuntimes: () async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "list", "-j")
    }
}
