import SwiftUI
import AppleAPI

struct SignIn2FAView: View {
    @Bindable var authenticationStore: AuthenticationStore
    @Binding var isPresented: Bool
    @State private var code: String = ""
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(String(format: localizeString("DigitCodeDescription"), authOptions.securityCode!.length))
                .fixedSize(horizontal: true, vertical: false)
            
            HStack {
                Spacer()
                PinCodeTextField(code: $code, numberOfDigits: authOptions.securityCode!.length) {
                    authenticationStore.submitSecurityCode(.device(code: $0), sessionData: sessionData)
                }
                Spacer()
            }
            .padding()
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Button("SendSMS", action: { authenticationStore.choosePhoneNumberForSMS(authOptions: authOptions, sessionData: sessionData) })
                Spacer()
                ProgressButton(isInProgress: authenticationStore.isProcessingAuthRequest,
                               action: { authenticationStore.submitSecurityCode(.device(code: code), sessionData: sessionData) }) {
                    Text("Continue")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.count != authOptions.securityCode!.length)
            }
            .frame(height: 25)
        }
        .padding()
        .emittingError($authenticationStore.authError, recoveryHandler: { _ in })
    }
}

struct SignIn2FAView_Previews: PreviewProvider {
    static var previews: some View {
        SignIn2FAView(
            authenticationStore: AuthenticationStore(),
            isPresented: .constant(true),
            authOptions: AuthOptionsResponse(
                trustedPhoneNumbers: nil,
                trustedDevices: nil,
                securityCode: .init(length: 6)
            ),
            sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
        )
    }
}
