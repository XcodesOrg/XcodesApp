import Foundation
import XcodesKit

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

enum XcodeListArchitecture: String, CaseIterable, Identifiable, CustomStringConvertible {
    case universal
    case appleSilicon
    
    var id: Self { self }
    
    var description: String {
        switch self {
            case .universal: return localizeString("Universal")
            case .appleSilicon: return localizeString("Apple Silicon")
        }
    }
    
    var isManaged: Bool { PreferenceKey.xcodeListCategory.isManaged() }
}
