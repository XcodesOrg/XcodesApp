import Foundation
import Path

public enum Downloader: String, CaseIterable, Identifiable, CustomStringConvertible {
    case aria2
    case urlSession
    
    public var id: Self { self }
    
    public var description: String {
        switch self {
        case .urlSession: return "URLSession"
        case .aria2: return "aria2"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .aria2: return Current.shell.aria2Path() != nil
        case .urlSession: return true
        }
    }

    var isManaged: Bool { PreferenceKey.downloader.isManaged() }
}
