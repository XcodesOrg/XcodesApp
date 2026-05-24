import Foundation

public enum SelectedActionType: String, CaseIterable, CustomStringConvertible, Identifiable, Sendable {
    case none
    case rename

    public var id: Self { self }

    public static var `default`: SelectedActionType { .none }

    public var description: String {
        switch self {
        case .none: return localizeString("OnSelectDoNothing")
        case .rename: return localizeString("OnSelectRenameXcode")
        }
    }

    public var detailedDescription: String {
        switch self {
        case .none: return localizeString("OnSelectDoNothingDescription")
        case .rename: return localizeString("OnSelectRenameXcodeDescription")
        }
    }
}
