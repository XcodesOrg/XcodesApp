import Foundation

enum XcodeListCategory: String, CaseIterable, Identifiable, CustomStringConvertible {
    case all
    case installed
    
    var id: Self { self }
    
    var description: String {
        switch self {
            case .all: return "All"
            case .installed: return "Installed"
        }
    }
}
