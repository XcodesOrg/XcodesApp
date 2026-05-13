import AppKit
import Sparkle
import SwiftUI
import XcodesKit

private enum HelpMenuURL {
    static let xcodesRepo = URL(string: "https://github.com/XcodesOrg/XcodesApp/")!
    // swiftlint:disable:next line_length
    static let bugReport = URL(string: "https://github.com/XcodesOrg/XcodesApp/issues/new?assignees=&labels=bug&template=bug_report.md&title=")!
    // swiftlint:disable:next line_length
    static let featureRequest = URL(string: "https://github.com/XcodesOrg/XcodesApp/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=")!
}

@main
struct XcodesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    @SwiftUI.Environment(\.scenePhase) private var scenePhase: ScenePhase
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    @StateObject private var appState = AppState()
    @StateObject private var updater = ObservableUpdater()

    var body: some Scene {
        Window("Xcodes", id: "main") {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(updater)
                // This is intentionally used on a View, and not on a WindowGroup,
                // so that it's triggered when an individual window's phase changes instead of all window phases.
                // When used on a View it's also invoked on launch, which doesn't occur with a WindowGroup.
                // FB8954581 ScenePhase read from App doesn't return appState value on launch
                .onChange(of: scenePhase) { _, newScenePhase in
                    guard !isTesting else { return }
                    if case .active = newScenePhase {
                        appState.updateIfNeeded()
                        appState.updateInstalledRuntimes()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Xcodes") {
                    appDelegate.showAboutWindow()
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
                Button("Xcodes GitHub Repo") {
                    openURL(HelpMenuURL.xcodesRepo)
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
                PreferencesView()
                    .environmentObject(appState)
                    .environmentObject(updater)
                    .alert(item: $appState.presentedPreferenceAlert, content: { presentedAlert in
                        alert(for: presentedAlert)
                    })
            }

            Window("Platforms", id: "platforms") {
                PlatformsListView()
                    .environmentObject(appState)
                    .alert(item: $appState.presentedPreferenceAlert, content: { presentedAlert in
                        alert(for: presentedAlert)
                    })
            }
        #endif
    }

    private func alert(for alertType: XcodesPreferencesAlert) -> Alert {
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

class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    @MainActor
    private lazy var aboutWindow = configure(NSWindow(
        contentRect: .zero,
        styleMask: [.closable, .resizable, .miniaturizable, .titled],
        backing: .buffered,
        defer: false
    )) {
        $0.title = "About"
        $0.contentView = NSHostingView(rootView: AboutView(showAcknowledgementsWindow: { [weak self] in
            self?.showAcknowledgementsWindow()
        }))
        $0.isReleasedWhenClosed = false
    }

    @MainActor
    private let acknowledgementsWindow = configure(NSWindow(
        contentRect: .zero,
        styleMask: [.closable, .resizable, .miniaturizable, .titled],
        backing: .buffered,
        defer: false
    )) {
        $0.title = "Acknowledgements"
        $0.contentView = NSHostingView(rootView: AcknowledgmentsView())
        $0.isReleasedWhenClosed = false
    }

    /// If we wanted to use only SwiftUI API to do this we could make a new WindowGroup and use openURL and
    /// handlesExternalEvents.
    /// WindowGroup lets the user open more than one window right now, which is a little strange for an About window.
    /// (It's also weird that the main Xcode list window can be opened more than once, there should only be one.)
    /// To work around this, an AppDelegate holds onto a single instance of an NSWindow that is shown here.
    /// FB8954588 Scene / WindowGroup is missing API to limit the number of windows that can be created
    @MainActor
    func showAboutWindow() {
        aboutWindow.center()
        aboutWindow.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showAcknowledgementsWindow() {
        acknowledgementsWindow.center()
        acknowledgementsWindow.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_: Notification) {}

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        current.defaults.bool(forKey: "terminateAfterLastWindowClosed") ?? false
    }
}
