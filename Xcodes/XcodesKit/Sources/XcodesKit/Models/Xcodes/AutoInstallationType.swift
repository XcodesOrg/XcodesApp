import Foundation

public enum AutoInstallationType: Int, Identifiable, Sendable {
    case none = 0
    case newestVersion
    case newestBeta

    public var id: Self { self }

    public var isAutoInstalling: Bool {
        get { self != .none }
        set {
            self = newValue ? .newestVersion : .none
        }
    }

    public var isAutoInstallingBeta: Bool {
        get { self == .newestBeta }
        set {
            self = newValue ? .newestBeta : (isAutoInstalling ? .newestVersion : .none)
        }
    }
}
