import Foundation
import AppleAPI

enum XcodesSheet: Identifiable {
    case signIn
    case twoFactor(SecondFactorData)
    case securityKeyTouchToConfirm

    var id: Int { Kind(self).hashValue }

    struct SecondFactorData {
        let option: TwoFactorOption
        let authOptions: AuthOptionsResponse
        let sessionData: AppleSessionData
    }
}

extension XcodesSheet {
    private enum Kind: Hashable {
        case signIn, twoFactor(TwoFactorOption), securityKeyTouchToConfirm

        enum TwoFactorOption {
            case smsSent
            case codeSent
            case smsPendingChoice
            case securityKeyPin
        }

        init(_ sheet: XcodesSheet) {
            switch sheet {
            case .signIn: self = .signIn
            case .twoFactor(let data):
                switch data.option {
                case .smsSent: self = .twoFactor(.smsSent)
                case .smsPendingChoice: self = .twoFactor(.smsPendingChoice)
                case .codeSent: self = .twoFactor(.codeSent)
                case .securityKey: self = .twoFactor(.securityKeyPin)
                }
            case .securityKeyTouchToConfirm: self = .securityKeyTouchToConfirm
            }
        }
    }
}
