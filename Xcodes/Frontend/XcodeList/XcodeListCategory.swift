import Foundation

enum XcodeListCategory: String, CaseIterable, Identifiable, CustomStringConvertible {
    case all
    case release
    case beta
    
    var id: Self { self }
    
    var description: String {
        switch self {
            case .all: return localizeString("All")
            case .release: return localizeString("Release")
            case .beta: return localizeString("Beta")
        }
    }

    var isManaged: Bool { PreferenceKey.xcodeListCategory.isManaged() }
}
