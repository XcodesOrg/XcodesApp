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
        ToolbarItemGroup(placement: .status) {
            Button(action: { appState.presentedSheet = .signIn }, label: {
                Label("Login", systemImage: "person.circle")
            })
            .help("Login")

            ProgressButton(
                isInProgress: appState.isUpdating, 
                action: appState.update
            ) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(KeyEquivalent("r"))
            .help("Refresh")
            
            Button(action: {
                switch category {
                case .all: category = .release
                case .release: category = .beta
                case .beta: category = .all
                }
            }) {
                switch category {
                case .all:
                    Label("All", systemImage: "line.horizontal.3.decrease.circle")
                case .release:
                    if #available(macOS 11.3, *) {
                        Label("Release only", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleAndIconLabelStyle())
                            .foregroundColor(.accentColor)
                    } else {
                        Label("Release only", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleOnlyLabelStyle())
                            .foregroundColor(.accentColor)
                    }
                case .beta:
                    if #available(macOS 11.3, *) {
                        Label("Beta only", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleAndIconLabelStyle())
                            .foregroundColor(.accentColor)
                    } else {
                        Label("Beta only", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(TitleOnlyLabelStyle())
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .help("Filter available versions")
            
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
            .help("Filter installed versions")
            
            Button(action: { isShowingInfoPane.toggle() }) {
                if isShowingInfoPane {
                    Label("Info", systemImage: "info.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Label("Info", systemImage: "info.circle")
                }
            }
            .keyboardShortcut(KeyboardShortcut("i", modifiers: [.command, .option]))
            .help("Show or hide the info pane")

            TextField("Search...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
                .help("Search list")
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
