import ErrorHandling
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedXcodeID: Xcode.ID?
    @State private var searchText: String = ""
    @AppStorage("lastUpdated") private var lastUpdated: Double?
    // These two properties should be per-scene state managed by @SceneStorage property wrappers.
    // There's currently a bug with @SceneStorage on macOS, though, where quitting the app will discard the values, which removes a lot of its utility.
    // In the meantime, we're using @AppStorage so that persistence and state restoration works, even though it's not per-scene.
    // FB8979533 SceneStorage doesn't restore value after app is quit by user
    @AppStorage("isShowingInfoPane") private var isShowingInfoPane = false
    @AppStorage("xcodeListCategory") private var category: XcodeListCategory = .all
    @AppStorage("isInstalledOnly") private var isInstalledOnly = false
  
    var body: some View {
        HSplitView {
            XcodeListView(selectedXcodeID: $selectedXcodeID, searchText: searchText, category: category, isInstalledOnly: isInstalledOnly)
                .frame(minWidth: 300)
                .layoutPriority(1)
                .alert(item: $appState.xcodeBeingConfirmedForUninstallation) { xcode in
                    Alert(title: Text(String(format: localizeString("Alert.Uninstall.Title"), xcode.description)),
                          message: Text("Alert.Uninstall.Message"),
                          primaryButton: .destructive(Text("Uninstall"), action: { self.appState.uninstall(xcode: xcode) }),
                          secondaryButton: .cancel(Text("Cancel")))
                }
            
            if isShowingInfoPane {
                InfoPane(selectedXcodeID: selectedXcodeID)
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
        }
        .mainToolbar(
            category: $category,
            isInstalledOnly: $isInstalledOnly,
            isShowingInfoPane: $isShowingInfoPane,
            searchText: $searchText
        )
        .navigationSubtitle(subtitleText)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .emittingError($appState.error, recoveryHandler: { _ in })
        .sheet(item: $appState.presentedSheet) { sheet in
            switch sheet {
            case .signIn:
                signInView()
                    .environmentObject(appState)
            case .twoFactor:
                secondFactorView(appState.secondFactorData!)
                    .environmentObject(appState)
            }
        }
        .alert(item: $appState.presentedAlert, content: { presentedAlert in
            alert(for: presentedAlert)
        })
        // I'm expecting to be able to use this modifier on a List row, but using it at the top level here is the only way that has made XcodeCommands work so far.
        // FB8954571 focusedValue(_:_:) on List row doesn't propagate value to @FocusedValue
        .focusedValue(\.selectedXcode, SelectedXcode(appState.allXcodes.first { $0.id == selectedXcodeID }))
    }
    
    private var subtitleText: Text {
        if let lastUpdated = lastUpdated.map(Date.init(timeIntervalSince1970:)) {
            return Text("\(localizeString("UpdatedAt")) \(lastUpdated, style: .date) \(lastUpdated, style: .time)")
        } else {
            return Text("")
        }
    }
    
    @ViewBuilder
    private func secondFactorView(_ secondFactorData: AppState.SecondFactorData) -> some View {
        switch secondFactorData.option {
        case .codeSent:
            SignIn2FAView(isPresented: $appState.secondFactorData.isNotNil, authOptions: secondFactorData.authOptions, sessionData: secondFactorData.sessionData)
        case .smsSent(let trustedPhoneNumber):
            SignInSMSView(isPresented: $appState.secondFactorData.isNotNil, trustedPhoneNumber: trustedPhoneNumber, authOptions: secondFactorData.authOptions, sessionData: secondFactorData.sessionData)
        case .smsPendingChoice:
            SignInPhoneListView(isPresented: $appState.secondFactorData.isNotNil, authOptions: secondFactorData.authOptions, sessionData: secondFactorData.sessionData)
        }
    }

    @ViewBuilder
    private func signInView() -> some View {
        if appState.authenticationState == .authenticated {
            VStack {
                SignedInView()
                    .padding(32)
                HStack {
                    Spacer()
                    Button("Close") { appState.presentedSheet = nil }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
        } else {
            SignInCredentialsView()
                .frame(width: 400)
        }
    }

    private func alert(for alertType: XcodesAlert) -> Alert {
        switch alertType {
        case let .cancelInstall(xcode):
            return Alert(
                title: Text(String(format: "Alert.CancelInstall.Title", xcode.description)),
                  message: Text("Alert.CancelInstall.Message"),
                  primaryButton: .destructive(
                    Text("Alert.CancelInstall.PrimaryButton"),
                    action: {
                        self.appState.cancelInstall(id: xcode.id)
                    }
                  ),
                  secondaryButton: .cancel(Text("Cancel"))
            )
        case .privilegedHelper:
            return Alert(
                title: Text("Alert.PrivilegedHelper.Title"),
                message: Text("Alert.PrivilegedHelper.Message"),
                primaryButton: .default(Text("Install"), action: {
                    // The isPreparingUserForActionRequiringHelper closure is set to nil by the alert's binding when its dismissed.
                    // We need to capture it to be invoked after that happens.
                    let helperAction = appState.isPreparingUserForActionRequiringHelper
                    DispatchQueue.main.async {
                        // This really shouldn't be nil, but sometimes this alert is being shown twice and I don't know why.
                        // There are some DispatchQueue.main.async's scattered around which make this better but in some situations it's still happening.
                        // When that happens, the second time the user clicks an alert button isPreparingUserForActionRequiringHelper will be nil.
                        // To at least not crash, we're using ?
                        helperAction?(true)
                        appState.presentedAlert = nil
                    }
                }),
                secondaryButton: .cancel {
                    // The isPreparingUserForActionRequiringHelper closure is set to nil by the alert's binding when its dismissed.
                    // We need to capture it to be invoked after that happens.
                    let helperAction = appState.isPreparingUserForActionRequiringHelper
                    DispatchQueue.main.async {
                        // This really shouldn't be nil, but sometimes this alert is being shown twice and I don't know why.
                        // There are some DispatchQueue.main.async's scattered around which make this better but in some situations it's still happening.
                        // When that happens, the second time the user clicks an alert button isPreparingUserForActionRequiringHelper will be nil.
                        // To at least not crash, we're using ?
                        helperAction?(false)
                        appState.presentedAlert = nil
                    }
                }
            )
        case let .generic(title, message):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(
                    Text("Ok"),
                    action: { appState.presentedAlert = nil }
                )
            )
        case let .checkMinSupportedVersion(xcode, deviceVersion):
            return Alert(
                title: Text("Alert.MinSupported.Title"),
                message: Text(String(format: "Alert.MinSupported.Message", xcode.version.descriptionWithoutBuildMetadata, xcode.requiredMacOSVersion ?? "", deviceVersion)),
                  primaryButton: .default(
                    Text("Install"),
                    action: {
                        self.appState.install(id: xcode.version)
                    }
                  ),
                  secondaryButton: .cancel(Text("Cancel"))
            )
        }
    }
}

struct MainWindow_Previews: PreviewProvider {
    static var previews: some View {
        MainWindow()
    }
}
