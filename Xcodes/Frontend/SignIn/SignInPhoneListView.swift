import AppleAPI
import SwiftUI

struct SignInPhoneListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var selectedPhoneNumberID: AuthOptionsResponse.TrustedPhoneNumber.ID?
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData

    var body: some View {
        VStack(alignment: .leading) {
            if let phoneNumbers = authOptions.trustedPhoneNumbers, !phoneNumbers.isEmpty {
                Text(String(format: localizeString("SelectTrustedPhone"), authOptions.securityCode!.length))

                List(phoneNumbers, selection: $selectedPhoneNumberID) {
                    Text($0.numberWithDialCode)
                }
                .onAppear {
                    if phoneNumbers.count == 1 {
                        selectedPhoneNumberID = phoneNumbers.first?.id
                    }
                }
            } else {
                Text("NoTrustedPhones")
                    .font(.callout)
                Spacer()
            }

            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ProgressButton(isInProgress: appState.isProcessingAuthRequest,
                               action: { appState.requestSMS(to: authOptions.trustedPhoneNumbers!.first { $0.id == selectedPhoneNumberID }!, authOptions: authOptions, sessionData: sessionData) })
                {
                    Text("Continue")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPhoneNumberID == nil)
            }
            .frame(height: 25)
        }
        .padding()
        .frame(width: 400, height: 200)
        .emittingError($appState.authError, recoveryHandler: { _ in })
    }
}

struct SignInPhoneListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SignInPhoneListView(
                isPresented: .constant(true),
                authOptions: AuthOptionsResponse(
                    trustedPhoneNumbers: [.init(id: 0, numberWithDialCode: "(•••) •••-••90")],
                    trustedDevices: nil,
                    securityCode: .init(length: 6)
                ),
                sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
            )
            .environmentObject(AppState())

            SignInPhoneListView(
                isPresented: .constant(true),
                authOptions: AuthOptionsResponse(
                    trustedPhoneNumbers: [],
                    trustedDevices: nil,
                    securityCode: .init(length: 6)
                ),
                sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
            )
            .environmentObject(AppState())
        }
    }
}
