import SwiftUI

struct SignInCredentialsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var username: String = ""
    @State private var password: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Sign in with your Apple ID.")
                .bold()
                .padding(.vertical)
            HStack {
                Text("Apple ID:")
                    .frame(minWidth: 100, alignment: .trailing)
                TextField("example@icloud.com", text: $username)
                    .frame(width: 250)
            }
            HStack {
                Text("Password:")
                    .frame(minWidth: 100, alignment: .trailing)
                SecureField("Required", text: $password)
                    .frame(width: 250)
            }
            
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Next") { appState.signIn(username: username, password: password) }
                    .disabled(username.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

struct SignInCredentialsView_Previews: PreviewProvider {
    static var previews: some View {
        SignInCredentialsView(isPresented: .constant(true))
            .environmentObject(AppState())
    }
}
