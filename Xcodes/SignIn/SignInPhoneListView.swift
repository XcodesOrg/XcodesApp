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
                // TODO: This should be a clickable hyperlink
                Text("Your account doesn't have any trusted phone numbers, but they're required for two-factor authentication. See https://support.apple.com/en-ca/HT204915.")
                    // lineLimit doesn't work, fixedSize(horizontal: false, vertical: true) is too large in an Alert
                    .frame(height: 50)
            }
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue", action: { appState.requestSMS(to: authOptions.trustedPhoneNumbers!.first { $0.id == selectedPhoneNumberID }!, authOptions: authOptions, sessionData: sessionData) })
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedPhoneNumberID == nil)
            }
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
