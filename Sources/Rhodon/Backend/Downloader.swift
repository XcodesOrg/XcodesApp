import Foundation
import Path

public enum Downloader: String, CaseIterable, Identifiable, CustomStringConvertible {
    case aria2
    case urlSession

    public var id: Self {
        self
    }

    public var description: String {
        switch self {
        case .urlSession: "URLSession"
        case .aria2: "aria2"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .aria2: current.shell.aria2Path() != nil
        case .urlSession: true
        }
    }

    var isManaged: Bool {
        PreferenceKey.downloader.isManaged()
    }
}
