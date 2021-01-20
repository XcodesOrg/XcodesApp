import AppleAPI
import Preferences
import SwiftUI

extension Preferences.PaneIdentifier {
    static let general = Self("general")
}

struct GeneralPreferencePane: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Preferences.Container(contentWidth: 400.0) {
            Preferences.Section(title: "Apple ID") {
                VStack(alignment: .leading) {
                    if appState.authenticationState == .authenticated {
                        Text(Current.defaults.string(forKey: "username") ?? "-")
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
