import SwiftUI

struct SignInCredentialsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var username: String = ""
    @State private var password: String = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Apple ID")
                TextField("Apple ID", text: $username)
            }
            
            HStack {
                Text("Password")
                SecureField("Password", text: $password)
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Sign In") {
                    appState.continueLogin(username: username, password: password) 
                }
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
