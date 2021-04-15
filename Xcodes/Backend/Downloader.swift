import Foundation
import Path

public enum Downloader: String, CaseIterable, Identifiable, CustomStringConvertible {
    #if arch(x86_64)
    case aria2
    #endif
    case urlSession
    
    public var id: Self { self }
    
    public var description: String {
        switch self {
        case .urlSession: return "URLSession"
        #if arch(x86_64)
        case .aria2: return "aria2"
        #endif
        }
    }
}
