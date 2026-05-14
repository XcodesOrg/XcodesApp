import Foundation
import RhodonKit

enum XcodeListCategory: String, CaseIterable, Identifiable, CustomStringConvertible {
    case all
    case release
    case beta

    var id: Self {
        self
    }

    var description: String {
        switch self {
        case .all: "All"
        case .release: "Release"
        case .beta: "Beta"
        }
    }

    var isManaged: Bool {
        PreferenceKey.xcodeListCategory.isManaged()
    }
}

enum XcodeListArchitecture: String, CaseIterable, Identifiable, CustomStringConvertible {
    case universal
    case appleSilicon

    var id: Self {
        self
    }

    var description: String {
        switch self {
        case .universal: "Universal"
        case .appleSilicon: "Apple Silicon"
        }
    }

    var isManaged: Bool {
        PreferenceKey.xcodeListCategory.isManaged()
    }
}
