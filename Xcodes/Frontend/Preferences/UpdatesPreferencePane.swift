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
                    .disabled(updater.disableAutoInstallNewVersions)

                    Toggle(
                        "IncludePreRelease",
                        isOn: $autoInstallationType.isAutoInstallingBeta
                    )
                    .disabled(updater.disableIncludePrereleaseVersions)
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
                    .disabled(updater.disableAutoUpdateXcodesApp)

                    Toggle(
                        "IncludePreRelease",
                        isOn: $updater.includePrereleaseVersions
                    )
                    .disabled(updater.disableAutoUpdateXcodesAppPrereleaseVersions)

                    Button("CheckNow") {
                        updater.checkForUpdates()
                    }
                    .padding(.top)
                    .disabled(updater.disableAutoUpdateXcodesApp)

                    Text(String(format: localizeString("LastChecked"), lastUpdatedString))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
    private let updaterDelegate = UpdaterDelegate()
    
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
            Current.defaults.set(includePrereleaseVersions, forKey: "includePrereleaseVersions")

            updaterDelegate.includePrereleaseVersions = includePrereleaseVersions
        }
    }

    var disableAutoInstallNewVersions: Bool { PreferenceKey.autoInstallation.isManaged() }
    var disableIncludePrereleaseVersions: Bool { PreferenceKey.autoInstallation.isManaged() }

    var disableAutoUpdateXcodesApp: Bool { PreferenceKey.SUEnableAutomaticChecks.isManaged() }
    var disableAutoUpdateXcodesAppPrereleaseVersions: Bool { PreferenceKey.includePrereleaseVersions.isManaged() }

    init() {
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil).updater
        
        // upgrade from an old sparkle version which set feeds via the updater
        // now it uses the `updaterDelegate`
        updater.clearFeedURLFromUserDefaults()
        
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
        includePrereleaseVersions = Current.defaults.bool(forKey: "includePrereleaseVersions") ?? false
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var includePrereleaseVersions: Bool = false
    
    func feedURLString(for updater: SPUUpdater) -> String? {
        if includePrereleaseVersions {
            return .prereleaseAppcast
        } else {
            return .appcast
        }
    }
}


extension String {
    static let appcast = "https://www.xcodes.app/appcast.xml"
    static let prereleaseAppcast = "https://www.xcodes.app/appcast_pre.xml"
}

struct UpdatesPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UpdatesPreferencePane()
                .environmentObject(AppState())
                .environmentObject(ObservableUpdater())
                .frame(maxWidth: 600)
                .frame(minHeight: 300)
        }
    }
}
