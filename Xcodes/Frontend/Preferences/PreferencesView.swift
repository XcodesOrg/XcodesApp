import SwiftUI

struct PreferencesView: View {
    private enum Tabs: Hashable, CaseIterable {
        case general, updates, downloads, advanced, experiment

        var title: LocalizedStringKey {
            switch self {
            case .general: return "General"
            case .updates: return "Updates"
            case .downloads: return "Downloads"
            case .advanced: return "Advanced"
            case .experiment: return "Experiments"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .updates: return "arrow.triangle.2.circlepath.circle"
            case .downloads: return "icloud.and.arrow.down"
            case .advanced: return "gearshape.2"
            case .experiment: return "lightbulb"
            }
        }
    }

    @State private var selectedTab = Tabs.general
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: ObservableUpdater

    var body: some View {
        VStack(spacing: 20) {
            // Native Settings toolbar images can retain the first tab's accent tint.
            HStack(spacing: 4) {
                ForEach(Tabs.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tab.symbol)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 24))
                                .frame(height: 28)
                            Text(tab.title)
                        }
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralPreferencePane()
                        .environmentObject(appState)
                case .updates:
                    UpdatesPreferencePane()
                        .environmentObject(updater)
                case .downloads:
                    DownloadPreferencePane()
                        .environmentObject(appState)
                case .advanced:
                    AdvancedPreferencePane()
                        .environmentObject(appState)
                case .experiment:
                    ExperimentsPreferencePane()
                        .environmentObject(appState)
                }
            }
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
