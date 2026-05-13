import AppleAPI
import Path
import SwiftUI
import Version
import XcodesKit

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedXcodeID: Xcode.ID?
    @State private var searchText: String = ""
    @AppStorage("lastUpdated") private var lastUpdated: Double?
    // These two properties should be per-scene state managed by @SceneStorage property wrappers.
    // There's currently a bug with @SceneStorage on macOS, though, where quitting the app will discard the values,
    // which removes a lot of its utility.
    // In the meantime, we're using @AppStorage so that persistence and state restoration works, even though it's not
    // per-scene.
    // FB8979533 SceneStorage doesn't restore value after app is quit by user
    @AppStorage("isShowingInfoPane") private var isShowingInfoPane = false
    @AppStorage("xcodeListCategory") private var category: XcodeListCategory = .all
    @AppStorage("xcodeListArchitecture") private var architecture: XcodeListArchitecture = .universal
    @AppStorage("isInstalledOnly") private var isInstalledOnly = false

    var body: some View {
        NavigationSplitViewWrapper {
            XcodeListView(
                selectedXcodeID: $selectedXcodeID,
                searchText: searchText,
                category: category,
                isInstalledOnly: isInstalledOnly,
                architecture: architecture
            )
            .layoutPriority(1)
            .alert(item: $appState.xcodeBeingConfirmedForUninstallation) { xcode in
                Alert(
                    title: Text("Uninstall Xcode \(xcode.description)?"),
                    message: Text("Alert.Uninstall.Message"),
                    primaryButton: .destructive(Text("Uninstall"), action: { appState.uninstall(xcode: xcode) }),
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
            .searchable(text: $searchText, placement: .sidebar)
            .mainToolbar(
                category: $category,
                isInstalledOnly: $isInstalledOnly,
                isShowingInfoPane: $isShowingInfoPane,
                architecture: $architecture
            )
        } detail: {
            Group {
                if let xcode {
                    InfoPane(xcode: xcode)
                } else {
                    UnselectedView()
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button(action: { appState.presentedSheet = .signIn }, label: {
                        Label("Login", systemImage: "person.circle")
                    })
                    .help("LoginDescription")
                    if #available(macOS 14, *) {
                        SettingsLink(label: {
                            Label("Preferences", systemImage: "gearshape")
                        })
                        .help("PreferencesDescription")
                    } else {
                        Button(action: {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }, label: {
                            Label("Preferences", systemImage: "gearshape")
                        })
                        .help("PreferencesDescription")
                    }
                }
            }
        }
        .bottomStatusBar()
        .padding([.top], 0)
        .navigationSubtitle(subtitleText)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .emittingError($appState.error, recoveryHandler: { _ in })
        .sheet(item: $appState.presentedSheet) { sheet in
            switch sheet {
            case .signIn:
                signInView()
                    .environmentObject(appState)
            case let .twoFactor(secondFactorData):
                secondFactorView(secondFactorData)
            }
        }
        .alert(item: $appState.presentedAlert, content: { presentedAlert in
            alert(for: presentedAlert)
        })
        // I'm expecting to be able to use this modifier on a List row, but using it at the top level here is the only
        // way that has made XcodeCommands work so far.
        // FB8954571 focusedValue(_:_:) on List row doesn't propagate value to @FocusedValue
        .focusedValue(\.selectedXcode, SelectedXcode(appState.allXcodes.first { $0.id == selectedXcodeID }))
    }

    private var xcode: Xcode? {
        appState.allXcodes.first(where: { $0.id == selectedXcodeID })
    }

    private var subtitleText: Text {
        if let lastUpdated = lastUpdated.map(Date.init(timeIntervalSince1970:)) {
            Text("\("Updated at") \(lastUpdated, style: .date) \(lastUpdated, style: .time)")
        } else {
            Text("")
        }
    }

    @ViewBuilder
    private func secondFactorView(_ secondFactorData: XcodesSheet.SecondFactorData) -> some View {
        switch secondFactorData.option {
        case .codeSent:
            SignIn2FAView(
                authenticationStore: appState.authenticationStore,
                isPresented: $appState.presentedSheet.isNotNil,
                authOptions: secondFactorData.authOptions,
                sessionData: secondFactorData.sessionData
            )
        case let .smsSent(trustedPhoneNumber):
            SignInSMSView(
                authenticationStore: appState.authenticationStore,
                isPresented: $appState.presentedSheet.isNotNil,
                trustedPhoneNumber: trustedPhoneNumber,
                authOptions: secondFactorData.authOptions,
                sessionData: secondFactorData.sessionData
            )
        case .smsPendingChoice:
            SignInPhoneListView(
                authenticationStore: appState.authenticationStore,
                isPresented: $appState.presentedSheet.isNotNil,
                authOptions: secondFactorData.authOptions,
                sessionData: secondFactorData.sessionData
            )
        }
    }

    @ViewBuilder
    private func signInView() -> some View {
        if appState.authenticationStore.authenticationState == .authenticated {
            VStack {
                SignedInView(authenticationStore: appState.authenticationStore)
                    .padding(32)
                HStack {
                    Spacer()
                    Button("Close") { appState.presentedSheet = nil }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
        } else {
            SignInCredentialsView(authenticationStore: appState.authenticationStore) {
                appState.presentedSheet = nil
            }
            .frame(width: 400)
        }
    }

    private func alert(for alertType: XcodesAlert) -> Alert {
        switch alertType {
        case let .cancelInstall(xcode):
            cancelInstallAlert(for: xcode)
        case .privilegedHelper:
            privilegedHelperAlert()
        case let .generic(title, message):
            genericAlert(title: title, message: message)
        case .unauthenticated:
            unauthenticatedAlert()
        case let .checkMinSupportedVersion(xcode, deviceVersion):
            minSupportedVersionAlert(xcode: xcode, deviceVersion: deviceVersion)
        case let .cancelRuntimeInstall(runtime):
            cancelRuntimeInstallAlert(for: runtime)
        }
    }

    private func cancelInstallAlert(for xcode: Xcode) -> Alert {
        Alert(
            title: Text("Are you sure you want to stop the installation of Xcode \(xcode.description)?"),
            message: Text("Alert.CancelInstall.Message"),
            primaryButton: .destructive(
                Text("Alert.CancelInstall.PrimaryButton"),
                action: { appState.cancelInstall(id: xcode.id) }
            ),
            secondaryButton: .cancel(Text("Cancel"))
        )
    }

    private func privilegedHelperAlert() -> Alert {
        Alert(
            title: Text("Alert.PrivilegedHelper.Title"),
            message: Text("Alert.PrivilegedHelper.Message"),
            primaryButton: .default(Text("Install"), action: { handleHelperAlertResponse(true) }),
            secondaryButton: .cancel { handleHelperAlertResponse(false) }
        )
    }

    private func handleHelperAlertResponse(_ userConsented: Bool) {
        let helperAction = appState.isPreparingUserForActionRequiringHelper
        DispatchQueue.main.async {
            helperAction?(userConsented)
            appState.presentedAlert = nil
        }
    }

    private func genericAlert(title: String, message: String) -> Alert {
        Alert(
            title: Text(title),
            message: Text(message),
            dismissButton: .default(
                Text("OK"),
                action: { appState.presentedAlert = nil }
            )
        )
    }

    private func unauthenticatedAlert() -> Alert {
        Alert(
            title: Text("Alert.Install.Error.Title"),
            message: Text("Alert.Install.AuthError.Message"),
            primaryButton: .default(
                Text("OK"),
                action: { appState.presentedSheet = .signIn }
            ),
            secondaryButton: .cancel(Text("Cancel"))
        )
    }

    private func minSupportedVersionAlert(xcode: AvailableXcode, deviceVersion: String) -> Alert {
        Alert(
            title: Text("Alert.MinSupported.Title"),
            message: Text(
                // swiftlint:disable:next line_length
                "Xcode \(xcode.xcodeID.version.descriptionWithoutBuildMetadata) requires macOS \(xcode.requiredMacOSVersion ?? ""), but you are running macOS \(deviceVersion), do you still want to install it?"
            ),
            primaryButton: .default(
                Text("Install"),
                action: { appState.install(id: xcode.xcodeID) }
            ),
            secondaryButton: .cancel(Text("Cancel"))
        )
    }

    private func cancelRuntimeInstallAlert(for runtime: DownloadableRuntime) -> Alert {
            Alert(
                title: Text("Are you sure you want to stop the installation of Xcode \(runtime.name)?"),
                message: Text("Alert.CancelInstall.Message"),
                primaryButton: .destructive(
                    Text("Alert.CancelInstall.PrimaryButton"),
                    action: {
                        appState.cancelRuntimeInstall(runtime: runtime)
                    }
                ),
                secondaryButton: .cancel(Text("Cancel"))
            )
    }
}

struct MainWindow_Previews: PreviewProvider {
    static var previews: some View {
        MainWindow().environmentObject({ () -> AppState in
            let appState = AppState()
            appState.allXcodes = [
                Xcode(
                    version: Version("12.0.0+1234A")!,
                    identicalBuilds: [
                        XcodeID(version: Version("12.0.0+1234A")!),
                        XcodeID(version: Version("12.0.0-RC+1234A")!)
                    ],
                    installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                    selected: false,
                    icon: nil
                ),
                Xcode(
                    version: Version("12.3.0")!,
                    installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                    selected: true,
                    icon: nil
                ),
                Xcode(version: Version("12.2.0")!, installState: .notInstalled, selected: false, icon: nil),
                Xcode(
                    version: Version("12.1.0")!,
                    installState: .installing(.downloading(progress: configure(Progress(totalUnitCount: 100)) {
                        $0.completedUnitCount = 40
                    })),
                    selected: false,
                    icon: nil
                ),
                Xcode(
                    version: Version("12.0.0")!,
                    installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                    selected: false,
                    icon: nil
                )
            ]
            return appState
        }())
    }
}
