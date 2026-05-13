import SwiftUI

struct SignInCredentialsView: View {
    private enum FocusedField {
        case username, password
    }

    @Bindable var authenticationStore: AuthenticationStore
    let cancel: () -> Void
    @State private var username: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Sign in with your Apple ID.")
                .bold()
                .padding(.vertical)
            HStack {
                Text("AppleID:")
                    .frame(minWidth: 100, alignment: .trailing)
                TextField(text: $username) {
                    Text(verbatim: "example@icloud.com")
                }
                .focused($focusedField, equals: .username)
            }
            HStack {
                Text("Password:")
                    .frame(minWidth: 100, alignment: .trailing)
                SecureField("Required", text: $password)
                    .focused($focusedField, equals: .password)
            }
            if authenticationStore.authError != nil {
                HStack {
                    Text("")
                        .frame(minWidth: 100)
                    Text(authenticationStore.authError?.legibleLocalizedDescription ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.red)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    authenticationStore.authError = nil
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                ProgressButton(
                    isInProgress: authenticationStore.isProcessingAuthRequest,
                    action: { authenticationStore.signIn(username: username, password: password) },
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
        SignInCredentialsView(authenticationStore: AuthenticationStore(), cancel: {})
            .previewLayout(.sizeThatFits)
    }
}
