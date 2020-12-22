import AppleAPI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("Apple ID")) {
                VStack(alignment: .leading) {
                    switch appState.authenticationState {
                    case .authenticated:
                        Text("Signed in")
                        Button("Sign Out", action: {})
                        
                    case .unauthenticated:
                        Button("Sign In", action: { self.appState.presentingSignInAlert = true })
                            .sheet(isPresented: $appState.presentingSignInAlert) {
                                SignInCredentialsView(isPresented: $appState.presentingSignInAlert)
                                    .environmentObject(appState)
                            }
                        
                    case .waitingForSecondFactor:
                        Button("Signing In...", action: {})
                            .disabled(true)
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
                .environmentObject(configure(AppState()) {
                    $0.authenticationState = .authenticated
                })
            
            SettingsView()
                .environmentObject(configure(AppState()) {
                    $0.authenticationState = .unauthenticated
                })
            
            SettingsView()
                .environmentObject(configure(AppState()) {
                    $0.authenticationState = .waitingForSecondFactor(
                        TwoFactorOption.codeSent,
                        AuthOptionsResponse(trustedPhoneNumbers: nil, trustedDevices: nil, securityCode: .init(length: 6)), 
                        AppleSessionData(serviceKey: "", sessionID: "", scnt: "")
                    )
                })
        }
    }
}
