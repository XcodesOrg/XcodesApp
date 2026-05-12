import Foundation
import AppleAPI

enum XcodesSheet: Identifiable {
    case signIn
    case twoFactor(SecondFactorData)

    var id: Int { Kind(self).hashValue }

    struct SecondFactorData {
        let option: TwoFactorOption
        let authOptions: AuthOptionsResponse
        let sessionData: AppleSessionData
    }
}

extension XcodesSheet {
    private enum Kind: Hashable {
        case signIn, twoFactor(TwoFactorOption)

        enum TwoFactorOption {
            case smsSent
            case codeSent
            case smsPendingChoice
        }

        init(_ sheet: XcodesSheet) {
            switch sheet {
            case .signIn: self = .signIn
            case .twoFactor(let data):
                switch data.option {
                case .smsSent: self = .twoFactor(.smsSent)
                case .smsPendingChoice: self = .twoFactor(.smsPendingChoice)
                case .codeSent: self = .twoFactor(.codeSent)
                }
            }
        }
    }
}
