import AppleAPI
import SwiftUI

struct GeneralPreferencePane: View {
    @EnvironmentObject var appState: AppState
   
    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("Apple ID")) {
                    // If we have saved a username then we will show it here,
                    // even if we don't have a valid session right now,
                    // because we should be able to get a valid session if needed with the password in the keychain 
                    // and a 2FA code from the user.
                    // Note that AppState.authenticationState is not necessarily .authenticated in this case, though.
                    if let username = Current.defaults.string(forKey: "username") {
                        HStack(alignment:.top, spacing: 10) {
                            Text(username)
                            Button("Sign Out", action: appState.signOut)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Button("Sign In", action: { self.appState.presentingSignInAlert = true })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            .sheet(isPresented: $appState.presentingSignInAlert) {
                SignInCredentialsView(isPresented: $appState.presentingSignInAlert)
                    .environmentObject(appState)
            }
        }
        .padding()
        .frame(width: 500)
    }
}

struct GeneralPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GeneralPreferencePane()
                .environmentObject(AppState())
        }
    }
}
