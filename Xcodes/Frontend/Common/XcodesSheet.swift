import Foundation

enum XcodesSheet: Identifiable {
    case signIn
    case twoFactor

    var id: Int { hashValue }
}
