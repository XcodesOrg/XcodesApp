import AppleAPI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("Apple ID")) {
                VStack(alignment: .leading) {
                    if let username = Current.defaults.string(forKey: "username") {
                        Text(username)
                        Button("Sign Out", action: appState.logOut)
                    } else {
                        Button("Sign In", action: { self.appState.presentingSignInAlert = true })
                            .sheet(isPresented: $appState.presentingSignInAlert) {
                                SignInCredentialsView(isPresented: $appState.presentingSignInAlert)
                                    .environmentObject(appState)
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Settings")
        .frame(width: 300)
        .frame(minHeight: 300)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView()
                .environmentObject(AppState())
        }
    }
}
