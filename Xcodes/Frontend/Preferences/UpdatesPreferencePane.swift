import AppleAPI
import Sparkle
import SwiftUI

struct UpdatesPreferencePane: View {
    @StateObject var updater = ObservableUpdater()
    
    @AppStorage("autoInstallation") var autoInstallationType: AutoInstallationType = .none
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Versions")) {
                VStack(alignment: .leading) {
                    Toggle(
                        "Automatically install new versions of Xcode",
                        isOn: $autoInstallationType.isAutoInstalling
                    )
                    
                    Toggle(
                        "Include prerelease/beta versions",
                        isOn: $autoInstallationType.isAutoInstallingBeta
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            
            Divider()
            
            GroupBox(label: Text("Xcodes.app Updates")) {
                VStack(alignment: .leading) {
                    Toggle(
                        "Automatically check for app updates",
                        isOn: $updater.automaticallyChecksForUpdates
                    )
                    
                    Toggle(
                        "Include prerelease app versions",
                        isOn: $updater.includePrereleaseVersions
                    )
                    
                    Button("Check Now") {
                        SUUpdater.shared()?.checkForUpdates(nil)
                    }
                    
                    Text("Last checked: \(lastUpdatedString)")
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
        .frame(width: 400)
    }
    
    private var lastUpdatedString: String {
        if let lastUpdatedDate = updater.lastUpdateCheckDate {
            return Self.formatter.string(from: lastUpdatedDate)
        } else {
            return "Never"
        }
    }
    
    private static let formatter = configure(DateFormatter()) {
        $0.dateStyle = .medium
        $0.timeStyle = .medium
    }
}

class ObservableUpdater: ObservableObject {
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            SUUpdater.shared()?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
    @Published var lastUpdateCheckDate: Date?
    private var lastUpdateCheckDateObservation: NSKeyValueObservation?
    @Published var includePrereleaseVersions = false {
        didSet {
            UserDefaults.standard.setValue(includePrereleaseVersions, forKey: "includePrereleaseVersions")

            if includePrereleaseVersions {
                SUUpdater.shared()?.feedURL = .prereleaseAppcast
            } else {
                SUUpdater.shared()?.feedURL = .appcast
            }
        }
    }
    
    init() {
        automaticallyChecksForUpdatesObservation = SUUpdater.shared()?.observe(
            \.automaticallyChecksForUpdates, 
            options: [.initial, .new, .old],
            changeHandler: { [unowned self] updater, change in
                guard change.newValue != change.oldValue else { return }
                self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            }
        )
        lastUpdateCheckDateObservation = SUUpdater.shared()?.observe(
            \.lastUpdateCheckDate, 
            options: [.initial, .new, .old],
            changeHandler: { [unowned self] updater, change in
                self.lastUpdateCheckDate = updater.lastUpdateCheckDate
            }
        )
        includePrereleaseVersions = UserDefaults.standard.bool(forKey: "includePrereleaseVersions")
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
        }
    }
}
