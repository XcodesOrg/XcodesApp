import Sparkle
import SwiftUI
import RhodonKit

private enum HelpMenuURL {
    static let rhodonRepo = URL(string: "https://github.com/RhodonOrg/Rhodon/")!
    // swiftlint:disable:next line_length
    static let bugReport = URL(string: "https://github.com/RhodonOrg/Rhodon/issues/new?assignees=&labels=bug&template=bug_report.md&title=")!
    // swiftlint:disable:next line_length
    static let featureRequest = URL(string: "https://github.com/RhodonOrg/Rhodon/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=")!
}

@main
struct Rhodon: App {
    @SwiftUI.Environment(\.scenePhase) private var scenePhase: ScenePhase
    @SwiftUI.Environment(\.openWindow) private var openWindow
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    @State private var appState = AppState()
    @State private var updater = ObservableUpdater()

    var body: some Scene {
        Window("Rhodon", id: "main") {
            MainWindow()
                .environment(appState)
                .environment(updater)
                // This is intentionally used on a View, and not on a WindowGroup,
                // so that it's triggered when an individual window's phase changes instead of all window phases.
                // When used on a View it's also invoked on launch, which doesn't occur with a WindowGroup.
                // FB8954581 ScenePhase read from App doesn't return appState value on launch
                .onChange(of: scenePhase) { _, newScenePhase in
                    guard !isTesting else { return }
                    if case .active = newScenePhase {
                        appState.updateIfNeeded()
                        Task {
                            await appState.updateInstalledRuntimes()
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Rhodon") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
            }

            CommandGroup(after: CommandGroupPlacement.newItem) {
                Button("Refresh") {
                    appState.update()
                }
                .keyboardShortcut(KeyEquivalent("r"))
                .disabled(appState.isUpdating)
            }

            XcodeCommands(appState: appState)

            CommandGroup(replacing: CommandGroupPlacement.help) {
                Button("Rhodon GitHub Repo") {
                    openURL(HelpMenuURL.rhodonRepo)
                }

                Divider()

                Button("Report a Bug") {
                    openURL(HelpMenuURL.bugReport)
                }

                Button("Request a New Feature") {
                    openURL(HelpMenuURL.featureRequest)
                }
            }
        }
        #if os(macOS)
            Settings {
                @Bindable var appState = appState
                PreferencesView()
                    .environment(appState)
                    .environment(updater)
                    .alert(item: $appState.presentedPreferenceAlert, content: { presentedAlert in
                        alert(for: presentedAlert)
                    })
            }

            Window("Platforms", id: "platforms") {
                @Bindable var appState = appState
                PlatformsListView()
                    .environment(appState)
                    .alert(item: $appState.presentedPreferenceAlert, content: { presentedAlert in
                        alert(for: presentedAlert)
                    })
            }

            Window("About", id: "about") {
                AboutView()
            }
            .windowResizability(.contentSize)

            Window("Acknowledgements", id: "acknowledgements") {
                AcknowledgmentsView()
            }
            .windowResizability(.contentSize)
        #endif
    }

    private func alert(for alertType: RhodonPreferencesAlert) -> Alert {
        switch alertType {
        case let .deletePlatform(runtime):
            Alert(
                title: Text("Are you sure you want to delete \(runtime.name)?"),
                primaryButton: .destructive(
                    Text("Alert.DeletePlatform.PrimaryButton"),
                    action: {
                        Task {
                            do {
                                try await appState.deleteRuntime(runtime: runtime)
                            } catch {
                                let errorString = error.legibleLocalizedDescription
                                appState.presentedPreferenceAlert = .generic(title: "Error", message: errorString)
                            }
                        }
                    }
                ),
                secondaryButton: .cancel(Text("Cancel"))
            )
        case let .generic(title, message):
            Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(
                    Text("OK"),
                    action: { appState.presentedAlert = nil }
                )
            )
        }
    }
}
