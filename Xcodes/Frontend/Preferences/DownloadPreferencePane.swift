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
