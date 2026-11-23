import SwiftUI

struct SignInCredentialsView: View {
    private enum FocusedField {
        case username, password
    }
    
    @EnvironmentObject var appState: AppState
    @State private var username: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: FocusedField?
    @State private var canSignInWithTouchID = false
    
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
                .textContentType(.username)
                .focused($focusedField, equals: .username)
            }
            HStack {
                Text("Password")
                    .frame(minWidth: 100, alignment: .trailing)
                SecureField("Required", text: $password)
                    .textContentType(.password)
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
                if canSignInWithTouchID {
                    Button {
                        appState.signInWithTouchID(username: username)
                    } label: {
                        Label("SignInWithTouchID", systemImage: "touchid")
                    }
                    .disabled(appState.isProcessingAuthRequest || appState.isAuthenticatingWithTouchID)
                }
                Spacer()
                Button("Cancel") {
                    appState.cancelSignIn()
                }
                    .keyboardShortcut(.cancelAction)
                ProgressButton(
                    isInProgress: appState.isProcessingAuthRequest,
                    action: { appState.signIn(username: username, password: password.isEmpty ? nil : password) },
                    label: {
                        Text("Next")
                    }
                )
                .disabled(username.isEmpty || appState.isAuthenticatingWithTouchID)
                .keyboardShortcut(.defaultAction)
            }
            .frame(height: 25)
        }
        .padding()
        .onAppear {
            if username.isEmpty, let savedUsername = appState.savedUsername {
                username = savedUsername
            }
        }
        .task(id: username) {
            // Wait for typing to pause before checking the keychain, instead of reading it on every keystroke.
            if !canSignInWithTouchID {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            updateCanSignInWithTouchID()
        }
    }

    private func updateCanSignInWithTouchID() {
        canSignInWithTouchID = appState.canSignInWithTouchID(username: username)
    }
}

struct SignInCredentialsView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        SignInCredentialsView()
            .environmentObject(AppState())
            .previewLayout(.sizeThatFits)
    }
}
