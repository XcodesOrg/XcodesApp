import SwiftUI
import AppleAPI

struct SignIn2FAView: View {
    @EnvironmentObject var appState: AppState
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
                    appState.submitSecurityCode(.device(code: $0), sessionData: sessionData)
                }
                Spacer()
            }
            .padding()
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Button("SendSMS", action: { appState.choosePhoneNumberForSMS(authOptions: authOptions, sessionData: sessionData) })
                Spacer()
                ProgressButton(isInProgress: appState.isProcessingAuthRequest,
                               action: { appState.submitSecurityCode(.device(code: code), sessionData: sessionData) }) {
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

struct SignIn2FAView_Previews: PreviewProvider {
    static var previews: some View {
        SignIn2FAView(
            isPresented: .constant(true),
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
