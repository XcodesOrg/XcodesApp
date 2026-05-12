import SwiftUI

struct SignInCredentialsView: View {
    private enum FocusedField {
        case username, password
    }
    
    @EnvironmentObject var appState: AppState
    @State private var username: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("SignInWithApple")
                .bold()
                .padding(.vertical)
            HStack {
                Text("AppleID")
                    .frame(minWidth: 100, alignment: .trailing)
                TextField(text: $username) {
                    Text(verbatim: "example@icloud.com")
                }
                .focused($focusedField, equals: .username)
            }
            HStack {
                Text("Password")
                    .frame(minWidth: 100, alignment: .trailing)
                SecureField("Required", text: $password)
                    .focused($focusedField, equals: .password)
            }
            if appState.authError != nil {
                HStack {
                    Text("")
                        .frame(minWidth: 100)
                    Text(appState.authError?.legibleLocalizedDescription ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    appState.authError = nil
                    appState.presentedSheet = nil
                }
                    .keyboardShortcut(.cancelAction)
                ProgressButton(
                    isInProgress: appState.isProcessingAuthRequest,
                    action: { appState.signIn(username: username, password: password) },
                    label: {
                        Text("Next")
                    }
                )
                .disabled(username.isEmpty || password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .frame(height: 25)
        }
        .padding()
    }
}

struct SignInCredentialsView_Previews: PreviewProvider {
    static var previews: some View {
        SignInCredentialsView()
            .environmentObject(AppState())
            .previewLayout(.sizeThatFits)
    }
}
