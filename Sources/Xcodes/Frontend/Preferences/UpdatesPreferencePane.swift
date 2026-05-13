import AppleAPI
import Observation
import Sparkle
import SwiftUI

struct UpdatesPreferencePane: View {
    @SwiftUI.Environment(ObservableUpdater.self) private var updater

    @AppStorage("autoInstallation") var autoInstallationType: AutoInstallationType = .none

    var body: some View {
        @Bindable var updater = updater

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
@Observable
class ObservableUpdater {
    private let updater: SPUUpdater
    private let updaterDelegate = UpdaterDelegate()

    var automaticallyChecksForUpdates = false {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
    var lastUpdateCheckDate: Date?
    @ObservationIgnored private var lastUpdateCheckDateObservation: NSKeyValueObservation?
    var includePrereleaseVersions = false {
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
                Task {
                    await self?.updateAutomaticallyChecksForUpdates(automaticallyChecksForUpdates)
                }
            }
        )
        lastUpdateCheckDateObservation = updater.observe(
            \.lastUpdateCheckDate,
            options: [.initial, .new, .old],
            changeHandler: { [weak self] _, change in
                let lastUpdateCheckDate = change.newValue ?? nil
                Task {
                    await self?.updateLastUpdateCheckDate(lastUpdateCheckDate)
                }
            }
        )
        includePrereleaseVersions = current.defaults.bool(forKey: "includePrereleaseVersions") ?? false
    }

    @MainActor
    private func updateAutomaticallyChecksForUpdates(_ value: Bool) {
        automaticallyChecksForUpdates = value
    }

    @MainActor
    private func updateLastUpdateCheckDate(_ value: Date?) {
        lastUpdateCheckDate = value
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
                .environment(AppState())
                .environment(ObservableUpdater())
                .frame(maxWidth: 600)
                .frame(minHeight: 300)
        }
    }
}
