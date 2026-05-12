import Foundation

public struct XcodesKitEnvironment: Sendable {
    public var shell = XcodesShell()
}

public let Current = XcodesKitEnvironment()
