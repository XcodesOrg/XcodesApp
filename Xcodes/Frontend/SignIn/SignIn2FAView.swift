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
            Text("Enter the \(authOptions.securityCode.length) digit code from one of your trusted devices:")
            
            HStack {
                Spacer()
                PinCodeTextField(code: $code, numberOfDigits: authOptions.securityCode.length)
                Spacer()
            }
            .padding()
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Button("Send SMS", action: { appState.choosePhoneNumberForSMS(authOptions: authOptions, sessionData: sessionData) })
                Spacer()
                if appState.isProcessingRequest {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(x: 0.5, y: 0.5, anchor: .center)
                        .padding(.trailing, 22)
                } else {
                    Button("Continue", action: { appState.submitSecurityCode(.device(code: code), sessionData: sessionData) })
                        .keyboardShortcut(.defaultAction)
                        .disabled(code.count != authOptions.securityCode.length)
                }
            }
            .frame(height: 25)
        }
        .padding()
        .alert(item: $appState.authError) { error in
            Alert(title: Text(error.title),
                  message: Text(verbatim: error.message),
                  dismissButton: .default(Text("OK")))
        }
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
