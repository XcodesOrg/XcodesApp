import SwiftUI

struct PreferencesView: View {
    private enum Tabs: Hashable {
        case general, updates, advanced, experiment
    }

    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(ObservableUpdater.self) private var updater

    var body: some View {
        TabView {
            GeneralPreferencePane()
                .environment(appState)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tabs.general)
            UpdatesPreferencePane()
                .environment(updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle")
                }
                .tag(Tabs.updates)
            DownloadPreferencePane()
                .environment(appState)
                .tabItem {
                    Label("Downloads", systemImage: "icloud.and.arrow.down")
                }
            AdvancedPreferencePane()
                .environment(appState)
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
        .padding(20)
        .frame(width: 600)
    }
}
