import SwiftUI
import XcodesKit
import Version
import PromiseKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection = Set<String>()
    @State private var rowBeingConfirmedForUninstallation: AppState.XcodeVersion?
    @State private var category: Category = .all
    @State private var searchText: String = ""
    
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
    
    enum Category {
        case all, installed
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
                Button("Login", action: { self.appState.presentingSignInAlert = true })
                    .sheet(isPresented: $appState.presentingSignInAlert) {
                        SignInCredentialsView(isPresented: $appState.presentingSignInAlert)
                            .environmentObject(appState)
                    }
                Button(action: { self.appState.update() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut(KeyEquivalent("r"))
            }
            ToolbarItem(placement: .principal) {
                Picker("", selection: $category) {
                    Text("All")
                        .tag(Category.all)
                    Text("Installed")
                        .tag(Category.installed)
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
        .onAppear(perform: appState.load)
        .alert(item: $appState.error) { error in
            Alert(title: Text(error.title), 
                  message: Text(verbatim: error.message), 
                  dismissButton: .default(Text("OK")))
        }
        .alert(item: self.$rowBeingConfirmedForUninstallation) { row in
            Alert(title: Text("Uninstall Xcode \(row.title)?"), 
                  message: Text("It will be moved to the Trash, but won't be emptied."), 
                  primaryButton: .destructive(Text("Uninstall"), action: { self.appState.uninstall(id: row.id) }), 
                  secondaryButton: .cancel(Text("Cancel")))
        }
        .sheet(item: $appState.secondFactorSessionData) { sessionData in
            SignIn2FAView(isPresented: $appState.secondFactorSessionData.isNotNil, sessionData: sessionData)
                .environmentObject(appState)
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
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
