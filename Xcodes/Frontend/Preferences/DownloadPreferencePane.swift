import SwiftUI
import XcodesKit

struct DownloadPreferencePane: View {
    @EnvironmentObject var appState: AppState
    
    @AppStorage("dataSource") var dataSource: DataSource = .xcodeReleases
    @AppStorage("downloader") var downloader: Downloader = .aria2
    @AppStorage(AutoDownloadPlatformsSelection.defaultsKey) private var autoDownloadPlatforms = ""

    private var platformSelection: AutoDownloadPlatformsSelection {
        AutoDownloadPlatformsSelection(rawValue: autoDownloadPlatforms)
    }

    private var downloadsAllPlatforms: Binding<Bool> {
        Binding(
            get: { platformSelection.isAll },
            set: { isAll in
                var selection = platformSelection
                selection.isAll = isAll
                autoDownloadPlatforms = selection.rawValue
            }
        )
    }

    private func downloadsPlatform(_ platform: DownloadableRuntime.Platform) -> Binding<Bool> {
        Binding(
            get: { platformSelection.includes(platform) },
            set: { isOn in
                var selection = platformSelection
                if isOn {
                    selection.platforms.insert(platform)
                } else {
                    selection.platforms.remove(platform)
                }
                autoDownloadPlatforms = selection.rawValue
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("DataSource")) {
                VStack(alignment: .leading) {
                    Picker("DataSource", selection: $dataSource) {
                        ForEach(DataSource.allCases) { dataSource in
                            Text(dataSource.description)
                                .tag(dataSource)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Text("DataSourceDescription")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            .disabled(dataSource.isManaged)
            .onChange(of: dataSource) {
                // The cached list belongs to the previous source, so fetch the new one right away.
                appState.isChangingDataSource = true
                appState.update(restartingInFlightUpdate: true)
            }

            GroupBox(label: Text("Downloader")) {
                VStack(alignment: .leading) {
                    Picker("Downloader", selection: $downloader) {
                        ForEach(Downloader.allCases) { downloader in
                            Text(downloader.description)
                                .tag(downloader)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Text("DownloaderDescription")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            .disabled(downloader.isManaged)

            GroupBox(label: Text("AutoDownloadPlatforms")) {
                VStack(alignment: .leading) {
                    Toggle("AutoDownloadPlatforms.All", isOn: downloadsAllPlatforms)

                    HStack(spacing: 16) {
                        ForEach(AutoDownloadPlatformsSelection.choosablePlatforms, id: \.self) { platform in
                            Toggle(isOn: downloadsPlatform(platform)) {
                                Text(verbatim: platform.shortName)
                            }
                        }
                    }
                    .disabled(platformSelection.isAll)

                    Text("AutoDownloadPlatformsDescription")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
    }
}

struct DownloadPreferencePane_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            DownloadPreferencePane()
                .environmentObject(AppState())
                .frame(maxWidth: 600)
                .frame(minHeight: 300)
        }
    }
}
