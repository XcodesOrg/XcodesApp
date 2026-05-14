import Foundation

extension Bundle {
    static var rhodonTests: Bundle {
        Bundle(for: BundleMember.self)
    }
}

private class BundleMember {}
