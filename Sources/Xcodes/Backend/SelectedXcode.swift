import Foundation

/// As part of the unexpected way we have to use focusedValue in XcodesApp, we need to provide an `Optional<Xcode>` because there isn't always a selected Xcode in the focused window.
/// But FocusedValueKey.Value is already optional, because there might not be a focused UI element to begin with, so the type ends up being `Optional<Optional<Xcode>>`. 
/// This is weird enough, but I wasn't able to find a way to have FocusedXcodeKey.Value be `Optional<Optional<Xcode>>` and still compile.
/// There was always an error somewhere in either the use of @FocusedValue or FocusedValues.xcode or .focusedValue, as if it is only ever expecting a single level of optionality.
/// But! If we make our own Optional replica like SelectedXcode, it _does_ compile, and there's some more noise required to turn it back into an `Optional<Xcode>`.
/// All this to say, maybe one day we don't need to have this type at all.
enum SelectedXcode {
    case none
    case some(Xcode)
    
    init(_ optional: Optional<Xcode>) {
        switch optional {
        case .none: self = .none
        case let .some(xcode): self = .some(xcode)
        }
    }
    
    var asOptional: Xcode? {
        switch self {
        case .none: return .none
        case let .some(xcode): return .some(xcode)
        }
    }
}

extension Optional where Wrapped == SelectedXcode {
    var unwrapped: Xcode? {
        switch self {
        case Optional<SelectedXcode>.none: return Optional<Xcode>.none
        case let .some(selectedXcode): return selectedXcode.asOptional
        }
    }
}
