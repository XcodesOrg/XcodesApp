import AppleAPI
import SwiftUI

struct GeneralPreferencePane: View {
    @EnvironmentObject var appState: AppState
    @State var languages: [String: String] = [:]
    @State var currentLanguage: String? = ""
    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("AppleID")) {
                if appState.authenticationState == .authenticated {
                    SignedInView()
                } else {
                    Button("SignIn", action: { self.appState.presentedSheet = .signIn })
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            Divider()
            
            GroupBox(label: Text("Notifications")) {
                NotificationsView().environmentObject(appState)
            }
            
            .groupBoxStyle(PreferencesGroupBoxStyle())
            Divider()
            GroupBox(label: Text("Language")) {
                Picker("", selection: $currentLanguage) {
                    ForEach(languages.values.sorted(), id: \.self) { language in
                        Text(language)
                            .tag(language)
                    }
                }
                .onChange(of: currentLanguage!) { newLanguage in
                    if let langKey = languages.first(where: { $0.value == newLanguage })?.key {
                        changeAppLanguage(to: langKey)
                    }
                    
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            Divider()
            
            GroupBox(label: Text("Misc")) {
                Toggle("TerminateAfterLastWindowClosed", isOn: $appState.terminateAfterLastWindowClosed)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
        .onAppear {
            languages = getLocalizedLanguages()
            currentLanguage = languages[Current.defaults.string(forKey: "appLanguage") ?? "en"]
        }
    }
    
    func getLocalizedLanguages() -> [String : String] {
        let langIds = Bundle.main.localizations
        var languages = [String:String]()
        for langId in langIds {
            let loc = Locale(identifier: langId)
            if let name = loc.localizedString(forLanguageCode: langId) {
                languages[langId] = name
            }
        }
        return languages
    }
    
    func changeAppLanguage(to languageCode: String) {
        self.appState.appLanguage = languageCode
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
