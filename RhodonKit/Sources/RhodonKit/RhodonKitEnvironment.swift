import Foundation

public struct RhodonKitEnvironment: Sendable {
    public var shell = RhodonShell()
}

public let current = RhodonKitEnvironment()
