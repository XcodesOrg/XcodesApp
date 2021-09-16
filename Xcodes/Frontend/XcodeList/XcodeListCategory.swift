import Foundation

enum XcodeListCategory: String, CaseIterable, Identifiable, CustomStringConvertible {
    case all
    case release
    case beta
    
    var id: Self { self }
    
    var description: String {
        switch self {
            case .all: return "All"
            case .release: return "Release"
            case .beta: return "Beta"
        }
    }
}
