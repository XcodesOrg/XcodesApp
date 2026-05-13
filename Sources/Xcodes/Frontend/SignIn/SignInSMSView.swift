import AppleAPI
import SwiftUI

struct SignInSMSView: View {
    @Bindable var authenticationStore: AuthenticationStore
    @Binding var isPresented: Bool
    @State private var code: String = ""
    let trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData

    var body: some View {
        VStack(alignment: .leading) {
            Text(
                // swiftlint:disable:next line_length
                "Enter the \(authOptions.securityCode!.length) digit code sent to \(trustedPhoneNumber.numberWithDialCode): "
            )

            HStack {
                Spacer()
                PinCodeTextField(code: $code, numberOfDigits: authOptions.securityCode!.length) {
                    let code = $0
                    Task {
                        await authenticationStore.submitSecurityCode(
                            .sms(code: code, phoneNumberId: trustedPhoneNumber.id),
                            sessionData: sessionData
                        )
                    }
                }
                Spacer()
            }
            .padding()

            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ProgressButton(
                    isInProgress: authenticationStore.isProcessingAuthRequest,
                    action: {
                        await authenticationStore.submitSecurityCode(
                            .sms(code: code, phoneNumberId: trustedPhoneNumber.id),
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

struct SignInSMSView_Previews: PreviewProvider {
    static var previews: some View {
        SignInSMSView(
            authenticationStore: AuthenticationStore(),
            isPresented: .constant(true),
            trustedPhoneNumber: .init(id: 0, numberWithDialCode: "(•••) •••-••90"),
            authOptions: AuthOptionsResponse(
                trustedPhoneNumbers: nil,
                trustedDevices: nil,
                securityCode: .init(length: 6)
            ),
            sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
        )
    }
}
