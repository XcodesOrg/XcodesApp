import AppleAPI
import SwiftUI

struct GeneralPreferencePane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("AppleID:")) {
                if appState.authenticationStore.authenticationState == .authenticated {
                    SignedInView(authenticationStore: appState.authenticationStore)
                } else {
                    Button("Sign In", action: { appState.presentedSheet = .signIn })
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            Divider()

            GroupBox(label: Text("Notifications")) {
                NotificationsView().environmentObject(appState)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
    }
}

struct GeneralPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GeneralPreferencePane()
                .environmentObject(AppState())
                .frame(maxWidth: 600)
        }
    }
}
