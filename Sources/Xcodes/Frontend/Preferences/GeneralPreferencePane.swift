import AppleAPI
import SwiftUI

struct GeneralPreferencePane: View {
    @SwiftUI.Environment(AppState.self) private var appState

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
                NotificationsView().environment(appState)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
    }
}

struct GeneralPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GeneralPreferencePane()
                .environment(AppState())
                .frame(maxWidth: 600)
        }
    }
}
