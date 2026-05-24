import Foundation
@preconcurrency import Path

public extension Path {
    @discardableResult
    func setCurrentUserAsOwner() -> Path {
        let user = ProcessInfo.processInfo.environment["SUDO_USER"] ?? NSUserName()
        try? FileManager.default.setAttributes([.ownerAccountName: user], ofItemAtPath: string)
        return self
    }
}
