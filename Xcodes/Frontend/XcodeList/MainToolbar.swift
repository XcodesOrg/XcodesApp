import SwiftUI

struct MainToolbarModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @Binding var category: XcodeListView.Category
    @Binding var isShowingInfoPane: Bool
    @Binding var searchText: String
    
    func body(content: Content) -> some View {
        content
            .toolbar { toolbar }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
            ProgressButton(
                isInProgress: appState.isUpdating, 
                action: appState.update
            ) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(KeyEquivalent("r"))
            
            Button(action: {
                switch category {
                case .all: category = .installed
                case .installed: category = .all
                }
            }) {
                switch category {
                case .all:
                    Label("Filter", systemImage: "line.horizontal.3.decrease.circle")
                case .installed:
                    Label("Filter", systemImage: "line.horizontal.3.decrease.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }

            Button(action: { isShowingInfoPane.toggle() }) {
                if isShowingInfoPane {
                    Label("Inspector", systemImage: "info.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Label("Inspector", systemImage: "info.circle")
                }
            }
            .keyboardShortcut(KeyboardShortcut("i", modifiers: [.command, .option]))

            TextField("Search...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
        }
    }
}

extension View {
    func mainToolbar(
        category: Binding<XcodeListView.Category>,
        isShowingInfoPane: Binding<Bool>,
        searchText: Binding<String>
    ) -> some View {
        self.modifier(
            MainToolbarModifier(
                category: category,
                isShowingInfoPane: isShowingInfoPane,
                searchText: searchText
            )
        )
    }
}
