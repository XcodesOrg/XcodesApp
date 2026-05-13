import AppleAPI
import Foundation

enum XcodesSheet: Identifiable {
    case signIn
    case twoFactor(SecondFactorData)

    var id: Int {
        XcodesSheetKind(self).hashValue
    }

    struct SecondFactorData {
        let option: TwoFactorOption
        let authOptions: AuthOptionsResponse
        let sessionData: AppleSessionData
    }
}

private enum XcodesSheetKind: Hashable {
    case signIn, twoFactor(XcodesSheetSecondFactorKind)

    init(_ sheet: XcodesSheet) {
        switch sheet {
        case .signIn: self = .signIn
        case let .twoFactor(data):
            switch data.option {
            case .smsSent: self = .twoFactor(.smsSent)
            case .smsPendingChoice: self = .twoFactor(.smsPendingChoice)
            case .codeSent: self = .twoFactor(.codeSent)
            }
        }
    }
}

private enum XcodesSheetSecondFactorKind {
    case smsSent
    case codeSent
    case smsPendingChoice
}
