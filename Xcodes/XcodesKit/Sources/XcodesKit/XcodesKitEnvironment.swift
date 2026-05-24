import Foundation
import os

public final class XcodesKitEnvironment: Sendable {
    private let environment = OSAllocatedUnfairLock(initialState: Storage())

    public var files: XcodesKitFiles {
        get { environment.withLock { $0.files } }
        set { environment.withLock { $0.files = newValue } }
    }

    public var shell: XcodesShell {
        get { environment.withLock { $0.shell } }
        set { environment.withLock { $0.shell = newValue } }
    }

    public init() {}

    private struct Storage: Sendable {
        var files = XcodesKitFiles()
        var shell = XcodesShell()
    }
}

let Current = XcodesKitEnvironment()

public struct XcodesKitFiles: Sendable {
    public var contentsAtPath: @Sendable (String) -> Data? = {
        try? Data(contentsOf: URL(fileURLWithPath: $0))
    }

    public func contents(atPath path: String) -> Data? {
        contentsAtPath(path)
    }
}

public func configureXcodesKitFileContents(_ contentsAtPath: @escaping @Sendable (String) -> Data?) {
    var files = Current.files
    files.contentsAtPath = contentsAtPath
    Current.files = files
}

public func configureXcodesKitArchs(_ archs: @escaping @Sendable (URL) throws -> ProcessOutput) {
    var shell = Current.shell
    shell.archs = archs
    Current.shell = shell
}
