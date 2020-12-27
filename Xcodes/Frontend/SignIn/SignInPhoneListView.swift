import SwiftUI
import AppleAPI

struct SignInPhoneListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var selectedPhoneNumberID: AuthOptionsResponse.TrustedPhoneNumber.ID?
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData
    
    var body: some View {
        VStack(alignment: .leading) {
            if let phoneNumbers = authOptions.trustedPhoneNumbers, !phoneNumbers.isEmpty {
                Text("Select a trusted phone number to receive a \(authOptions.securityCode.length) digit code via SMS:")
                
                List(phoneNumbers, selection: $selectedPhoneNumberID) {
                    Text($0.numberWithDialCode)
                }
                .frame(height: 200)
            } else {
                AttributedText(
                    NSAttributedString(string: "Your account doesn't have any trusted phone numbers, but they're required for two-factor authentication. See https://support.apple.com/en-ca/HT204915.")
                        .convertingURLsToLinkAttributes()
                )
            }
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Spacer()

                if appState.isProcessingRequest {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(x: 0.5, y: 0.5, anchor: .center)
                        .padding(.trailing, 22)
                } else {
                    Button("Continue", action: { appState.requestSMS(to: authOptions.trustedPhoneNumbers!.first { $0.id == selectedPhoneNumberID }!, authOptions: authOptions, sessionData: sessionData) })
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedPhoneNumberID == nil)
                }
            }
            .frame(height: 25)
        }
        .padding()
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
                    securityCode: .init(length: 6)),
                sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
            )
            
            SignInPhoneListView(
                isPresented: .constant(true),
                authOptions: AuthOptionsResponse(
                    trustedPhoneNumbers: [], 
                    trustedDevices: nil,
                    securityCode: .init(length: 6)),
                sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
            )
        }
    }
}
