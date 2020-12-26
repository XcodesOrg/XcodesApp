import AppleAPI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("dataSource") var dataSource: DataSource = .xcodeReleases
    
    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("Apple ID")) {
                VStack(alignment: .leading) {
                    if let username = Current.defaults.string(forKey: "username") {
                        Text(username)
                        Button("Sign Out", action: appState.signOut)
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
            
            GroupBox(label: Text("Data Source")) {
                VStack(alignment: .leading) {
                    Picker("Data Source", selection: $dataSource) {
                        ForEach(DataSource.allCases) { dataSource in
                            Text(dataSource.description)
                                .tag(dataSource)
                        }
                    }
                    .labelsHidden()
                    
                    AttributedText(dataSourceFootnote)
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Text("Privileged Helper")) {
                VStack(alignment: .leading, spacing: 8) {
                    switch appState.helperInstallState {
                    case .unknown:
                        ProgressView()
                            .scaleEffect(0.5, anchor: .center)
                    case .installed:
                        Text("Helper is installed")
                    case .notInstalled:
                        HStack {
                            Text("Helper is not installed")
                            Button("Install helper") {
                                appState.installHelper()
                            }
                        }
                    }
                    
                    Text("Xcodes uses a separate privileged helper to perform tasks as root. These are things that would require sudo on the command line, including post-install steps and switching Xcode versions with xcode-select.")
                        .font(.footnote)
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Settings")
        .frame(width: 300)
        .frame(minHeight: 300)
    }
    
    private var dataSourceFootnote: NSAttributedString {
        let string = """
        The Apple data source scrapes the Apple Developer website. It will always show the latest releases that are available, but is more fragile.

        Xcode Releases is an unofficial list of Xcode releases. It's provided as well-formed data, contains extra information that is not readily available from Apple, and is less likely to break if Apple redesigns their developer website.
        """
        let attributedString = NSMutableAttributedString(
            string: string, 
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .footnote, options: [:]),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributedString.addAttribute(.link, value: URL(string: "https://xcodereleases.com")!, range: NSRange(string.range(of: "Xcode Releases")!, in: string))
        return attributedString
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
