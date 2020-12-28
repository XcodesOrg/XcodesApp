import SwiftUI

struct MainToolbarModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @Binding var category: XcodeListView.Category
    @Binding var searchText: String
    
    func body(content: Content) -> some View {
        content
            .toolbar { toolbar }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
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

            TextField("Search...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
        }
    }
}

extension View {
    func mainToolbar(
        category: Binding<XcodeListView.Category>, 
        searchText: Binding<String>
    ) -> some View {
        self.modifier(MainToolbarModifier(category: category, searchText: searchText))
    }
}
