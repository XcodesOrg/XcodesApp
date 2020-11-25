import SwiftUI
import XcodesKit
import Version
import PromiseKit

struct ContentView: View {
    @ObservedObject var appState = AppState()
    @State private var selection = Set<String>()
    @State private var rowBeingConfirmedForUninstallation: AppState.XcodeVersion?

    var body: some View {
        List(appState.allVersions, selection: $selection) { row in
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
                //                if row.installed {
                //                    HStack {
                //                        Button(action: { row.installed ? self.rowBeingConfirmedForUninstallation = row : self.appState.install(id: row.id) }) { 
                //                            Text("Uninstall") 
                //                        }
                //                        Button(action: { self.appState.reveal(id: row.id) }) {
                //                            Text("Reveal in Finder") 
                //                        }
                //                        Button(action: { self.appState.select(id: row.id) }) {
                //                            Text("Select") 
                //                        }
                //                    }
                //                    .buttonStyle(PlainButtonStyle())
                //                    .foregroundColor(
                //                        self.selection.contains(row.id) ?
                //                            Color(NSColor.selectedMenuItemTextColor) :
                //                            .accentColor
                //                    )
                //                }
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
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .onAppear(perform: appState.load)
        .toolbar {
            ToolbarItem {
                Button(action: { appState.update().cauterize() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r")
            }
        }
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
        .sheet(isPresented: $appState.presentingSignInAlert, content: {
            SignInCredentialsView(isPresented: $appState.presentingSignInAlert)
                .environmentObject(appState)
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
