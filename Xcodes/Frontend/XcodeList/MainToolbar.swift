import SwiftUI

struct MainToolbarModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @Binding var category: XcodeListCategory
    @Binding var isInstalledOnly: Bool
    @Binding var isShowingInfoPane: Bool

    func body(content: Content) -> some View {
        content
            .toolbar { toolbar }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            ProgressButton(
                isInProgress: appState.isUpdating,
                action: appState.update
            ) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(KeyEquivalent("r"))
            .help("RefreshDescription")
            Spacer()

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
                        Label("ReleaseOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .labelStyle(.trailingIcon)
                            .foregroundColor(.accentColor)
                case .beta:
                    Label("BetaOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                        .labelStyle(.trailingIcon)
                        .foregroundColor(.accentColor)
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
        }
    }
}

extension View {
    func mainToolbar(
        category: Binding<XcodeListCategory>,
        isInstalledOnly: Binding<Bool>,
        isShowingInfoPane: Binding<Bool>
    ) -> some View {
        modifier(
            MainToolbarModifier(
                category: category,
                isInstalledOnly: isInstalledOnly,
                isShowingInfoPane: isShowingInfoPane
            )
        )
    }
}
