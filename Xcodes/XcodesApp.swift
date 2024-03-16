import AppKit
import Sparkle
import SwiftUI

@main
struct XcodesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    @SwiftUI.Environment(\.scenePhase) private var scenePhase: ScenePhase
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    @StateObject private var appState = AppState()
    @StateObject private var updater = ObservableUpdater()

    var body: some Scene {
        WindowGroup("Xcodes") {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(updater)
                // This is intentionally used on a View, and not on a WindowGroup,
                // so that it's triggered when an individual window's phase changes instead of all window phases.
                // When used on a View it's also invoked on launch, which doesn't occur with a WindowGroup.
                // FB8954581 ScenePhase read from App doesn't return a value on launch
                .onChange(of: scenePhase) { newScenePhase in
                    guard !isTesting else { return }
                    if case .active = newScenePhase {
                        appState.updateIfNeeded()
                        appState.updateInstalledRuntimes()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Menu.About") {
                    appDelegate.showAboutWindow()
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Menu.CheckForUpdates") {
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
                Button("Menu.GitHubRepo") {
                    let xcodesRepoURL = URL(string: "https://github.com/RobotsAndPencils/XcodesApp/")!
                    openURL(xcodesRepoURL)
                }

                Divider()

                Button("Menu.ReportABug") {
                    let bugReportURL = URL(string: "https://github.com/RobotsAndPencils/XcodesApp/issues/new?assignees=&labels=bug&template=bug_report.md&title=")!
                    openURL(bugReportURL)
                }

                Button("Menu.RequestNewFeature") {
                    let featureRequestURL = URL(string: "https://github.com/RobotsAndPencils/XcodesApp/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=")!
                    openURL(featureRequestURL)
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
            return Alert(
                title: Text(String(format: localizeString("Alert.DeletePlatform.Title"), runtime.name)),
                  primaryButton: .destructive(
                    Text("Alert.DeletePlatform.PrimaryButton"),
                    action: {
                        Task {
                            do {
                                try await self.appState.deleteRuntime(runtime: runtime)
                            } catch {
                                var errorString: String
                                if let error = error as? String {
                                    errorString = error
                                } else {
                                    errorString = error.localizedDescription
                                }
                                self.appState.presentedPreferenceAlert = .generic(title: "Error", message: errorString)
                            }
                            
                        }
                    }
                  ),
                  secondaryButton: .cancel(Text("Cancel"))
            )
        case let .generic(title, message):
            return Alert(
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

class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var aboutWindow = configure(NSWindow(
        contentRect: .zero,
        styleMask: [.closable, .resizable, .miniaturizable, .titled],
        backing: .buffered,
        defer: false
    )) {
        $0.title = localizeString("About")
        $0.contentView = NSHostingView(rootView: AboutView(showAcknowledgementsWindow: showAcknowledgementsWindow))
        $0.isReleasedWhenClosed = false
    }

    private let acknowledgementsWindow = configure(NSWindow(
        contentRect: .zero,
        styleMask: [.closable, .resizable, .miniaturizable, .titled],
        backing: .buffered,
        defer: false
    )) {
        $0.title = localizeString("Acknowledgements")
        $0.contentView = NSHostingView(rootView: AcknowledgmentsView())
        $0.isReleasedWhenClosed = false
    }

    /// If we wanted to use only SwiftUI API to do this we could make a new WindowGroup and use openURL and handlesExternalEvents.
    /// WindowGroup lets the user open more than one window right now, which is a little strange for an About window.
    /// (It's also weird that the main Xcode list window can be opened more than once, there should only be one.)
    /// To work around this, an AppDelegate holds onto a single instance of an NSWindow that is shown here.
    /// FB8954588 Scene / WindowGroup is missing API to limit the number of windows that can be created
    func showAboutWindow() {
        aboutWindow.center()
        aboutWindow.makeKeyAndOrderFront(nil)
    }

    func showAcknowledgementsWindow() {
        acknowledgementsWindow.center()
        acknowledgementsWindow.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_: Notification) {}
}

func localizeString(_ key: String, comment: String = "") -> String {
    return String(localized: String.LocalizationValue(key))
}
