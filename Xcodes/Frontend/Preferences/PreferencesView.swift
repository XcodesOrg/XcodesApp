import SwiftUI

struct PreferencesView: View {
    private enum Tabs: Hashable {
        case general, updates, downloads, advanced, experiment
    }
    @State private var selectedTab = Tabs.general
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: ObservableUpdater
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencePane()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tabs.general)
            UpdatesPreferencePane()
                .environmentObject(updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle")
                }
                .tag(Tabs.updates)
            DownloadPreferencePane()
                .environmentObject(appState)
                .tabItem {
                    Label("Downloads", systemImage: "icloud.and.arrow.down")
                }
                .tag(Tabs.downloads)
            AdvancedPreferencePane()
                .environmentObject(appState)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(Tabs.advanced)
            ExperimentsPreferencePane()
                .tabItem {
                    Label("Experiments", systemImage: "lightbulb")
                }
                .tag(Tabs.experiment)
        }
        .onAppear { selectHelperSettingsIfRequested() }
        .onChange(of: appState.showHelperSettings) { _, _ in selectHelperSettingsIfRequested() }
        .padding(20)
        .frame(width: 600)
    }

    private func selectHelperSettingsIfRequested() {
        guard appState.showHelperSettings else { return }
        selectedTab = .advanced
        appState.showHelperSettings = false
    }
}
