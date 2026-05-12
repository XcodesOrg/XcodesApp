import SwiftUI

// MARK: - FocusedXcodeKey

struct FocusedXcodeKey : FocusedValueKey {
    typealias Value = SelectedXcode
}

// MARK: - FocusedValues

extension FocusedValues {
    var selectedXcode: FocusedXcodeKey.Value? {
        get { self[FocusedXcodeKey.self] }
        set { self[FocusedXcodeKey.self] = newValue }
    }
}
