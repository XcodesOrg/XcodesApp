import SwiftUI
import AppleAPI

struct SignInSMSView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var code: String = ""
    let trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(format: localizeString("EnterDigitCodeDescription"), authOptions.securityCode!.length, trustedPhoneNumber.numberWithDialCode))
            
            HStack {
                Spacer()
                PinCodeTextField(code: $code, numberOfDigits: authOptions.securityCode!.length) {
                    appState.submitSecurityCode(.sms(code: $0, phoneNumberId: trustedPhoneNumber.id), sessionData: sessionData)
                }
                Spacer()
            }
            .padding()
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ProgressButton(isInProgress: appState.isProcessingAuthRequest,
                               action: { appState.submitSecurityCode(.sms(code: code, phoneNumberId: trustedPhoneNumber.id), sessionData: sessionData) }) {
                    Text("Continue")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.count != authOptions.securityCode!.length)
            }
            .frame(height: 25)
        }
        .padding()
        .emittingError($appState.authError, recoveryHandler: { _ in })
    }
}

struct SignInSMSView_Previews: PreviewProvider {
    static var previews: some View {
        SignInSMSView(
            isPresented: .constant(true),
            trustedPhoneNumber: .init(id: 0, numberWithDialCode: "(•••) •••-••90"), 
            authOptions: AuthOptionsResponse(
                trustedPhoneNumbers: nil,
                trustedDevices: nil,
                securityCode: .init(length: 6)
            ),
            sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
        )
        .environmentObject(AppState())
    }
}
