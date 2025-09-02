import SwiftUI

struct MainToolbarModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @Binding var category: XcodeListCategory
    @Binding var isInstalledOnly: Bool
    @Binding var isShowingInfoPane: Bool
    @Binding var architectures: XcodeListArchitecture

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
            
            let isFiltering = isInstalledOnly || category != .all || architectures != .universal
            Menu("Filter", systemImage: "line.horizontal.3.decrease.circle") {
                Section {
                    Toggle("Installed Only", systemImage: "arrow.down.app", isOn: $isInstalledOnly)            .labelStyle(.titleAndIcon)
                }
                .help("FilterInstalledDescription")
                
                Section {
                    Picker("Category", selection: $category) {
                        Label("All", systemImage: "line.horizontal.3.decrease.circle")
                            .tag(XcodeListCategory.all)
                        Label("ReleaseOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .tag(XcodeListCategory.release)
                        Label("BetaOnly", systemImage: "line.horizontal.3.decrease.circle.fill")
                            .tag(XcodeListCategory.beta)
                    }
                }
                .help("FilterAvailableDescription")
                .disabled(category.isManaged)
                
                Section {
                    Picker("Architecture", selection: $architectures) {
                        Label("Universal", systemImage: "cpu.fill")
                            .tag(XcodeListArchitecture.universal)
                        Label("Apple Silicon", systemImage: "m4.button.horizontal")
                            .foregroundColor(.accentColor)
                            .tag(XcodeListArchitecture.appleSilicon)
                    }
                    .help("FilterArchitecturesDescription")
                    .disabled(architectures.isManaged)
                }
                .labelStyle(.titleAndIcon)
            }
            .pickerStyle(.inline)
            .symbolVariant(isFiltering ? .fill : .none)
        }
    }
}

extension View {
    func mainToolbar(
        category: Binding<XcodeListCategory>,
        isInstalledOnly: Binding<Bool>,
        isShowingInfoPane: Binding<Bool>,
        architecture: Binding<XcodeListArchitecture>
    ) -> some View {
        modifier(
            MainToolbarModifier(
                category: category,
                isInstalledOnly: isInstalledOnly,
                isShowingInfoPane: isShowingInfoPane,
                architectures: architecture
            )
        )
    }
}
