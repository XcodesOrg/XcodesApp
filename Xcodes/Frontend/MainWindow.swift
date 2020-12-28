import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: Xcode.ID?
    @State private var searchText: String = ""
    @AppStorage("lastUpdated") private var lastUpdated: Double?
    @SceneStorage("isShowingInfoPane") private var isShowingInfoPane = false
    @SceneStorage("xcodeListCategory") private var category: XcodeListCategory = .all

    var body: some View {
        HSplitView {
            XcodeListView(searchText: searchText, category: category)
                .frame(minWidth: 300)
                .layoutPriority(1)
            
            InspectorPane()
                .frame(minWidth: 300, maxWidth: .infinity)
                .frame(width: isShowingInfoPane ? nil : 0)
                .isHidden(!isShowingInfoPane)
        }
        .mainToolbar(
            category: $category,
            isShowingInfoPane: $isShowingInfoPane,
            searchText: $searchText
        )
        .navigationSubtitle(subtitleText)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .alert(item: $appState.error) { error in
            Alert(title: Text(error.title), 
                  message: Text(verbatim: error.message), 
                  dismissButton: .default(Text("OK")))
        }
        /*
         Removing this for now, because it's overriding the error alert that's being worked on above.
         .alert(item: $appState.xcodeBeingConfirmedForUninstallation) { xcode in
             Alert(title: Text("Uninstall Xcode \(xcode.description)?"), 
                   message: Text("It will be moved to the Trash, but won't be emptied."), 
                   primaryButton: .destructive(Text("Uninstall"), action: { self.appState.uninstall(id: xcode.id) }), 
                   secondaryButton: .cancel(Text("Cancel")))
         }
         **/
        .sheet(isPresented: $appState.secondFactorData.isNotNil) {
            secondFactorView(appState.secondFactorData!)
                .environmentObject(appState)
        }
    }
    
    private var subtitleText: Text {
        if let lastUpdated = lastUpdated.map(Date.init(timeIntervalSince1970:)) {
            return Text("Updated at \(lastUpdated, style: .date) \(lastUpdated, style: .time)")
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
}

struct MainWindow_Previews: PreviewProvider {
    static var previews: some View {
        MainWindow()
    }
}
