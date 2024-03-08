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
                    
                    AttributedText(dataSourceFootnote)
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
                    
                    AttributedText(downloaderFootnote)
                }
                
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            
        }
    }
    
    private var dataSourceFootnote: NSAttributedString {
        let string = localizeString("DataSourceDescription")
        let attributedString = NSMutableAttributedString(
            string: string,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .footnote, options: [:]),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        attributedString.addAttribute(.link, value: URL(string: "https://xcodereleases.com")!, range: NSRange(string.range(of: "Xcode Releases")!, in: string))
        return attributedString
    }
    
    private var downloaderFootnote: NSAttributedString {
        let string = localizeString("DownloaderDescription")
        let attributedString = NSMutableAttributedString(
            string: string,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .footnote, options: [:]),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        attributedString.addAttribute(.link, value: URL(string: "https://github.com/aria2/aria2")!, range: NSRange(string.range(of: "aria2")!, in: string))
        return attributedString
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
