import Foundation

extension Bundle {
    static var xcodesTests: Bundle {
        Bundle(for: BundleMember.self)
    }
}

private class BundleMember {}
