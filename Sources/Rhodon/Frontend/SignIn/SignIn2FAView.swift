import AppleAPI
import SwiftUI

struct SignIn2FAView: View {
    @Bindable var authenticationStore: AuthenticationStore
    @Binding var isPresented: Bool
    @State private var code: String = ""
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData

    var body: some View {
        VStack(alignment: .leading) {
            Text("Enter the \(authOptions.securityCode!.length) digit code from one of your trusted devices:")
                .fixedSize(horizontal: true, vertical: false)

            HStack {
                Spacer()
                PinCodeTextField(code: $code, numberOfDigits: authOptions.securityCode!.length) {
                    let code = $0
                    Task {
                        await authenticationStore.submitSecurityCode(.device(code: code), sessionData: sessionData)
                    }
                }
                Spacer()
            }
            .padding()

            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Button(
                    "SendSMS",
                    action: { authenticationStore.choosePhoneNumberForSMS(
                        authOptions: authOptions,
                        sessionData: sessionData
                    ) }
                )
                Spacer()
                ProgressButton(
                    isInProgress: authenticationStore.isProcessingAuthRequest,
                    action: {
                        await authenticationStore.submitSecurityCode(
                            .device(code: code),
                            sessionData: sessionData
                        )
                    },
                    label: {
                        Text("Continue")
                    }
                )
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
