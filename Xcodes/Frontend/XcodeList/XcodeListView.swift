import SwiftUI
import Version
import PromiseKit

struct XcodeListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection = Set<String>()
    @State private var rowBeingConfirmedForUninstallation: AppState.XcodeVersion?
    @State private var searchText: String = ""
    
    @AppStorage("xcodeListCategory") private var category: Category = .all
    
    var visibleVersions: [AppState.XcodeVersion] {
        var versions: [AppState.XcodeVersion]
        switch category {
        case .all:
            versions = appState.allVersions
        case .installed:
            versions = appState.allVersions.filter { $0.installed }
        }
        
        if !searchText.isEmpty {
            versions = versions.filter { $0.title.contains(searchText) }
        }
        
        return versions
    }
    
    enum Category: String, CaseIterable, Identifiable, CustomStringConvertible {
        case all
        case installed
        
        var id: Self { self }
        
        var description: String {
            switch self {
                case .all: return "All"
                case .installed: return "Installed"
            }
        }
    }
    
    var body: some View {
        List(visibleVersions, selection: $selection) { row in
            VStack(alignment: .leading) {
                HStack {
                    Text(row.title)
                        .font(.body)
                    if row.selected {
                        Tag(text: "SELECTED")
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Button(row.installed ? "INSTALLED" : "INSTALL") {
                        print("Installing...")
                    }
                    .buttonStyle(AppStoreButtonStyle(installed: row.installed,
                                                     highlighted: self.selection.contains(row.id)))
                    .disabled(row.installed)
                }
                Text(verbatim: row.path ?? "")
                    .font(.caption)
                    .foregroundColor(self.selection.contains(row.id) ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.secondaryLabelColor))
            }
            .contextMenu {
                Button(action: { row.installed ? self.rowBeingConfirmedForUninstallation = row : self.appState.install(id: row.id) }) { 
                    Text(row.installed ? "Uninstall" : "Install") 
                }
                if row.installed {
                    Button(action: { self.appState.reveal(id: row.id) }) {
                        Text("Reveal in Finder") 
                    }
                    Button(action: { self.appState.select(id: row.id) }) {
                        Text("Select") 
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: appState.update) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut(KeyEquivalent("r"))
                .disabled(appState.isUpdating)
                .isHidden(appState.isUpdating)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.5, anchor: .center)
                        .isHidden(!appState.isUpdating)
                )
            }
            ToolbarItem(placement: .principal) {
                Picker("", selection: $category) {
                    ForEach(Category.allCases, id: \.self) {
                        Text($0.description).tag($0)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            ToolbarItem {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
        }
        .navigationSubtitle(Text("Updated \(Date().addingTimeInterval(-600), style: .relative) ago"))
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .onAppear(perform: appState.update)
        .alert(item: $appState.error) { error in
            Alert(title: Text(error.title), 
                  message: Text(verbatim: error.message), 
                  dismissButton: .default(Text("OK")))
        }
        /*
         Removing this for now, because it's overriding the error alert that's being worked on above.
         .alert(item: self.$rowBeingConfirmedForUninstallation) { row in
             Alert(title: Text("Uninstall Xcode \(row.title)?"), 
                   message: Text("It will be moved to the Trash, but won't be emptied."), 
                   primaryButton: .destructive(Text("Uninstall"), action: { self.appState.uninstall(id: row.id) }), 
                   secondaryButton: .cancel(Text("Cancel")))
         }
         **/
        .sheet(isPresented: $appState.secondFactorData.isNotNil) {
            secondFactorView(appState.secondFactorData!)
                .environmentObject(appState)
        }
    }
    
    @ViewBuilder
    func secondFactorView(_ secondFactorData: AppState.SecondFactorData) -> some View {
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

struct XcodeListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            XcodeListView()
                .environmentObject({ () -> AppState in
                    let a = AppState()
                    a.allVersions = [
                        AppState.XcodeVersion(title: "12.3", installState: .installed, selected: true, path: nil),
                        AppState.XcodeVersion(title: "12.2", installState: .notInstalled, selected: false, path: nil),
                        AppState.XcodeVersion(title: "12.1", installState: .notInstalled, selected: false, path: nil),
                        AppState.XcodeVersion(title: "12.0", installState: .installed, selected: false, path: nil),
                    ]
                    return a
                }())
        }
        .previewLayout(.sizeThatFits)
    }
}

extension Optional {
    /// Note that this is lossy when setting, so you can really only set it to nil, but this is sufficient for mapping `Binding<Item?>` to `Binding<Bool>` for Alerts, Popovers, etc.
    var isNotNil: Bool {
        get { self != nil }
        set { self = newValue ? self : nil }
    }
}
