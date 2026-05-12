import Foundation

extension Optional {
    /// Note that this is lossy when setting, so you can really only set it to nil, but this is sufficient for mapping `Binding<Item?>` to `Binding<Bool>` for Alerts, Popovers, etc.
    var isNotNil: Bool {
        get { self != nil }
        set { self = newValue ? self : nil }
    }
}
