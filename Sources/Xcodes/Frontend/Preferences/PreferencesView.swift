import SwiftUI

struct PreferencesView: View {
    private enum Tabs: Hashable {
        case general, updates, advanced, experiment
    }
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: ObservableUpdater
    
    var body: some View {
        TabView {
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
        .padding(20)
        .frame(width: 600)
    }
}
