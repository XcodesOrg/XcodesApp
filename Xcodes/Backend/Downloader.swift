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

    var isManaged: Bool { PreferenceKey.downloader.isManaged() }
}
