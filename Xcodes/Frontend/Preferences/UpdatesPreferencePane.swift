import AppleAPI
import Sparkle
import SwiftUI

struct UpdatesPreferencePane: View {
    @EnvironmentObject var updater: ObservableUpdater
    
    @AppStorage("autoInstallation") var autoInstallationType: AutoInstallationType = .none
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Versions")) {
                VStack(alignment: .leading) {
                    Toggle(
                        "AutomaticInstallNewVersion",
                        isOn: $autoInstallationType.isAutoInstalling
                    )
                    
                    Toggle(
                        "IncludePreRelease",
                        isOn: $autoInstallationType.isAutoInstallingBeta
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            
            Divider()
            
            GroupBox(label: Text("AppUpdates")) {
                VStack(alignment: .leading) {
                    Toggle(
                        "CheckForAppUpdates",
                        isOn: $updater.automaticallyChecksForUpdates
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    
                    Toggle(
                        "IncludePreRelease",
                        isOn: $updater.includePrereleaseVersions
                    )
                    
                    Button("CheckNow") {
                        updater.checkForUpdates()
                    }
                    
                    Text(String(format: localizeString("LastChecked"), lastUpdatedString))
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
    }
    
    private var lastUpdatedString: String {
        if let lastUpdatedDate = updater.lastUpdateCheckDate {
            return Self.formatter.string(from: lastUpdatedDate)
        } else {
            return localizeString("Never")
        }
    }
    
    private static let formatter = configure(DateFormatter()) {
        $0.dateStyle = .medium
        $0.timeStyle = .medium
    }
}

class ObservableUpdater: ObservableObject {
    private let updater: SPUUpdater
      
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
    @Published var lastUpdateCheckDate: Date?
    private var lastUpdateCheckDateObservation: NSKeyValueObservation?
    @Published var includePrereleaseVersions = false {
        didSet {
            UserDefaults.standard.setValue(includePrereleaseVersions, forKey: "includePrereleaseVersions")

            if includePrereleaseVersions {
                updater.setFeedURL(.prereleaseAppcast)
            } else {
                updater.setFeedURL(.appcast)
            }
        }
    }
    
    init() {
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil).updater
        
        automaticallyChecksForUpdatesObservation = updater.observe(
            \.automaticallyChecksForUpdates, 
            options: [.initial, .new, .old],
            changeHandler: { [unowned self] updater, change in
                guard change.newValue != change.oldValue else { return }
                self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            }
        )
        lastUpdateCheckDateObservation = updater.observe(
            \.lastUpdateCheckDate, 
            options: [.initial, .new, .old],
            changeHandler: { [unowned self] updater, change in
                self.lastUpdateCheckDate = updater.lastUpdateCheckDate
            }
        )
        includePrereleaseVersions = UserDefaults.standard.bool(forKey: "includePrereleaseVersions")
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

extension URL {
    static let appcast = URL(string: "https://robotsandpencils.github.io/XcodesApp/appcast.xml")!
    static let prereleaseAppcast = URL(string: "https://robotsandpencils.github.io/XcodesApp/appcast_pre.xml")!
}

struct UpdatesPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UpdatesPreferencePane()
                .environmentObject(AppState())
                .frame(maxWidth: 500)
        }
    }
}
