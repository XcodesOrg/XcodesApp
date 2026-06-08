import Foundation
import XcodesKit

enum XcodeListCategory: String, CaseIterable, Identifiable, CustomStringConvertible {
    case all
    case release
    case beta
    case releasePlusNewBetas
    
    var id: Self { self }
    
    var description: String {
        switch self {
            case .all: return localizeString("All")
            case .release: return localizeString("Release")
            case .beta: return localizeString("Beta")
            case .releasePlusNewBetas: return localizeString("ReleasePlusNewBetas")
        }
    }

    var isManaged: Bool { PreferenceKey.xcodeListCategory.isManaged() }

    var versionFilter: XcodeListVersionFilter {
        switch self {
        case .all:
            return .all
        case .release:
            return .release
        case .beta:
            return .prerelease
        }
    }
}

enum XcodeListArchitecture: String, CaseIterable, Identifiable, CustomStringConvertible {
    case universal
    case appleSilicon
    
    var id: Self { self }

    static var defaultForCurrentMachine: Self {
        switch ArchitectureVariant.defaultForMachine() {
        case .universal:
            return .universal
        case .appleSilicon:
            return .appleSilicon
        }
    }
    
    var description: String {
        switch self {
            case .universal: return localizeString("Universal")
            case .appleSilicon: return localizeString("Apple Silicon")
        }
    }

    var menuDescription: String {
        isCurrentMachineDefault ? "\(description) (\(localizeString("This Mac")))" : description
    }
    
    var isCurrentMachineDefault: Bool {
        self == Self.defaultForCurrentMachine
    }
    
    var isManaged: Bool { PreferenceKey.xcodeListArchitectures.isManaged() }

    var architectureFilters: [ArchitectureFilter] {
        switch self {
        case .universal:
            return [.variant(.universal)]
        case .appleSilicon:
            return [.variant(.appleSilicon)]
        }
    }
}
