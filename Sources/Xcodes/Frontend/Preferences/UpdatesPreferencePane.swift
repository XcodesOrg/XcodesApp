import AppleAPI
import Combine
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
                        "Automatically install new versions of Xcode",
                        isOn: $autoInstallationType.isAutoInstalling
                    )
                    .disabled(updater.disableAutoInstallNewVersions)

                    Toggle(
                        "Include prerelease/beta versions",
                        isOn: $autoInstallationType.isAutoInstallingBeta
                    )
                    .disabled(updater.disableIncludePrereleaseVersions)
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
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(updater.disableAutoUpdateXcodesApp)

                    Toggle(
                        "Include prerelease/beta versions",
                        isOn: $updater.includePrereleaseVersions
                    )
                    .disabled(updater.disablePrereleaseAutoUpdates)

                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .padding(.top)
                    .disabled(updater.disableAutoUpdateXcodesApp)

                    Text("Last checked: \(lastUpdatedString)")
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
            Self.formatter.string(from: lastUpdatedDate)
        } else {
            "Never"
        }
    }

    private static let formatter = configure(DateFormatter()) {
        $0.dateStyle = .medium
        $0.timeStyle = .medium
    }
}

@MainActor
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
            current.defaults.set(includePrereleaseVersions, forKey: "includePrereleaseVersions")

            updaterDelegate.includePrereleaseVersions = includePrereleaseVersions
        }
    }

    var disableAutoInstallNewVersions: Bool {
        PreferenceKey.autoInstallation.isManaged()
    }

    var disableIncludePrereleaseVersions: Bool {
        PreferenceKey.autoInstallation.isManaged()
    }

    var disableAutoUpdateXcodesApp: Bool {
        PreferenceKey.SUEnableAutomaticChecks.isManaged()
    }

    var disablePrereleaseAutoUpdates: Bool {
        PreferenceKey.includePrereleaseVersions.isManaged()
    }

    init() {
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        ).updater

        // upgrade from an old sparkle version which set feeds via the updater
        // now it uses the `updaterDelegate`
        updater.clearFeedURLFromUserDefaults()

        automaticallyChecksForUpdatesObservation = updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.initial, .new, .old],
            changeHandler: { [weak self] _, change in
                guard
                    let automaticallyChecksForUpdates = change.newValue,
                    change.newValue != change.oldValue
                else { return }
                Task { @MainActor in
                    self?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
                }
            }
        )
        lastUpdateCheckDateObservation = updater.observe(
            \.lastUpdateCheckDate,
            options: [.initial, .new, .old],
            changeHandler: { [weak self] _, change in
                let lastUpdateCheckDate = change.newValue ?? nil
                Task { @MainActor in
                    self?.lastUpdateCheckDate = lastUpdateCheckDate
                }
            }
        )
        includePrereleaseVersions = current.defaults.bool(forKey: "includePrereleaseVersions") ?? false
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var includePrereleaseVersions: Bool = false

    func feedURLString(for _: SPUUpdater) -> String? {
        if includePrereleaseVersions {
            .prereleaseAppcast
        } else {
            .appcast
        }
    }
}

extension String {
    static let appcast = "https://www.xcodes.app/appcast.xml"
    static let prereleaseAppcast = "https://www.xcodes.app/appcast_pre.xml"
}

struct UpdatesPreferencePane_Previews: PreviewProvider {
    @MainActor
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
