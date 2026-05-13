import AppleAPI
import SwiftUI

struct DownloadPreferencePane: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("dataSource") var dataSource: DataSource = .xcodeReleases
    @AppStorage("downloader") var downloader: Downloader = .aria2

    var body: some View {
        VStack(alignment: .leading) {
            GroupBox(label: Text("Data Source")) {
                VStack(alignment: .leading) {
                    Picker("Data Source", selection: $dataSource) {
                        ForEach(DataSource.allCases) { dataSource in
                            Text(dataSource.description)
                                .tag(dataSource)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Text(
                        // swiftlint:disable:next line_length
                        "The Apple data source scrapes the Apple Developer website. It will always show the latest releases that are available, but is more fragile.\n\n[Xcode Releases](https://xcodereleases.com) is an unofficial list of [Xcode Releases](https://xcodereleases.com). It's provided as well-formed data, contains extra information that is not readily available from Apple, and is less likely to break if Apple redesigns their developer website."
                    )
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

                    Text(
                        // swiftlint:disable:next line_length
                        "[aria2](https://aria2.github.io) uses up to 16 connections to download Xcode 3-5x faster than URLSession. Xcodes uses a system-installed aria2c and does not bundle aria2. Install aria2 with Homebrew: brew install aria2. See the [Homebrew formula](https://formulae.brew.sh/formula/aria2).\n\nURLSession is the default Apple API for making URL requests."
                    )
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
