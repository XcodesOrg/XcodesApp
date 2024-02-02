import SwiftUI

struct MainToolbarModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @Binding var category: XcodeListCategory
    @Binding var isInstalledOnly: Bool
    @Binding var isShowingInfoPane: Bool
    @SwiftUI.Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .toolbar { self.toolbar }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            ProgressButton(
                isInProgress: self.appState.isUpdating,
                action: self.appState.update
            ) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(KeyEquivalent("r"))
            .help("RefreshDescription")
            Spacer()

            Button("Platforms", systemImage: "square.3.layers.3d") {
                self.openWindow(id: "platforms")
            }
            Button(action: {
                switch self.category {
                case .all: self.category = .release
                case .release: self.category = .beta
                case .beta: self.category = .all
                }
            }) {
                switch self.category {
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
                }
            }
            .help("FilterAvailableDescription")

            Button(action: {
                self.isInstalledOnly.toggle()
            }) {
                if self.isInstalledOnly {
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
        self.modifier(
            MainToolbarModifier(
                category: category,
                isInstalledOnly: isInstalledOnly,
                isShowingInfoPane: isShowingInfoPane
            )
        )
    }
}
