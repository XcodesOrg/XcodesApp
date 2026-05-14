import AppleAPI
import Foundation

enum RhodonSheet: Identifiable {
    case signIn
    case twoFactor(SecondFactorData)

    var id: Int {
        RhodonSheetKind(self).hashValue
    }

    struct SecondFactorData {
        let option: TwoFactorOption
        let authOptions: AuthOptionsResponse
        let sessionData: AppleSessionData
    }
}

private enum RhodonSheetKind: Hashable {
    case signIn, twoFactor(RhodonSheetSecondFactorKind)

    init(_ sheet: RhodonSheet) {
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

private enum RhodonSheetSecondFactorKind {
    case smsSent
    case codeSent
    case smsPendingChoice
}
