import AppleAPI
import Preferences
import SwiftUI

struct GeneralPreferencePane: View {
    @EnvironmentObject var appState: AppState
   
    var body: some View {
        Preferences.Container(contentWidth: 400.0) {
            Preferences.Section(title: "Apple ID") {
                VStack(alignment: .leading) {
                    // If we have saved a username then we will show it here,
                    // even if we don't have a valid session right now,
                    // because we should be able to get a valid session if needed with the password in the keychain 
                    // and a 2FA code from the user.
                    // Note that AppState.authenticationState is not necessarily .authenticated in this case, though.
                    if let username = Current.defaults.string(forKey: "username") {
                        Text(username)
                        Button("Sign Out", action: appState.signOut)
                    } else {
                        Button("Sign In", action: { self.appState.presentingSignInAlert = true })
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheet(isPresented: $appState.presentingSignInAlert) {
                    SignInCredentialsView(isPresented: $appState.presentingSignInAlert)
                        .environmentObject(appState)
                }
            }
        }
        .padding(.trailing)
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
