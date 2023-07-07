import SwiftUI

struct MainToolbarModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @Binding var category: XcodeListCategory
    @Binding var isInstalledOnly: Bool
    @Binding var isShowingInfoPane: Bool
    @Binding var searchText: String
    
    func body(content: Content) -> some View {
        content
            .toolbar { toolbar }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: { appState.presentedSheet = .signIn }, label: {
                Label("Login", systemImage: "person.circle")
            })
            .help("LoginDescription")
            
            ProgressButton(
                isInProgress: appState.isUpdating, 
                action: appState.update
            ) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(KeyEquivalent("r"))
            .help("RefreshDescription")
            
            Button(action: {
                switch category {
                case .all: category = .release
                case .release: category = .beta
                case .beta: category = .releasePlusNewBetas
                case .releasePlusNewBetas: category = .all
                }
            }) {
                switch category {
                case .all:
                    Label("All", systemImage: "line.horizontal.3.decrease.circle")
                case .release:
                    if #available(macOS 11.3, *) {
                        Label("ReleaseOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleAndIconLabelStyle())
                            .foregroundColor(.accentColor)
                    } else {
                        Label("ReleaseOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleOnlyLabelStyle())
                            .foregroundColor(.accentColor)
                    }
                case .beta:
                    if #available(macOS 11.3, *) {
                        Label("BetaOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleAndIconLabelStyle())
                            .foregroundColor(.accentColor)
                    } else {
                        Label("BetaOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleOnlyLabelStyle())
                            .foregroundColor(.accentColor)
                    }
                case .releasePlusBeta:
                    if #available(macOS 11.3, *) {
                        Label("ReleasePlusBetaOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleAndIconLabelStyle())
                            .foregroundColor(.accentColor)
                    } else {
                        Label("ReleasePlusBetaOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleOnlyLabelStyle())
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .help("FilterAvailableDescription")
            
            Button(action: {
                isInstalledOnly.toggle()
            }) {
                if isInstalledOnly {
                    Label("Filter", systemImage: "arrow.down.app.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Label("Filter", systemImage: "arrow.down.app")
                        
                }
            }
            .help("FilterInstalledDescription")
            
            Button(action: { isShowingInfoPane.toggle() }) {
                if isShowingInfoPane {
                    Label("Info", systemImage: "info.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Label("Info", systemImage: "info.circle")
                }
            }
            .keyboardShortcut(KeyboardShortcut("i", modifiers: [.command, .option]))
            .help("InfoDescription")
            
            Button(action: {
                if #available(macOS 13, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }   
            }, label: {
                Label("Preferences", systemImage: "gearshape")
            })
            .help("PreferencesDescription")
            
            TextField("Search", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
                .help("SearchDescription")
        }
    }
}

extension View {
    func mainToolbar(
        category: Binding<XcodeListCategory>,
        isInstalledOnly: Binding<Bool>,
        isShowingInfoPane: Binding<Bool>,
        searchText: Binding<String>
    ) -> some View {
        self.modifier(
            MainToolbarModifier(
                category: category,
                isInstalledOnly: isInstalledOnly,
                isShowingInfoPane: isShowingInfoPane,
                searchText: searchText
            )
        )
    }
}
