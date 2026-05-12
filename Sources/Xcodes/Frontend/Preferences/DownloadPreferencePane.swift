import AppleAPI
import SwiftUI

struct DownloadPreferencePane: View {
    @EnvironmentObject var appState: AppState
    
    @AppStorage("dataSource") var dataSource: DataSource = .xcodeReleases
    @AppStorage("downloader") var downloader: Downloader = .aria2
    
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

            GroupBox(label: Text("Downloader")) {
                VStack(alignment: .leading) {
                    Picker("Downloader", selection: $downloader) {
                        ForEach(Downloader.allCases) { option in
                            Text(option.description)
                                .tag(option)
                                .disabled(!option.isAvailable)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Text("DownloaderDescription")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !Downloader.aria2.isAvailable {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("aria2 is not available on this Mac. Install aria2 to use this option.")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Link("aria2", destination: Aria2UnavailableError.aria2HomepageURL)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Link("Homebrew formula", destination: Aria2UnavailableError.homebrewFormulaURL)
                            }
                            Text("The recommended installation command is `brew install aria2`.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            .disabled(downloader.isManaged)
        }
    }
}

struct DownloadPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DownloadPreferencePane()
                .environmentObject(AppState())
                .frame(maxWidth: 600)
                .frame(minHeight: 300)
        }
    }
}
