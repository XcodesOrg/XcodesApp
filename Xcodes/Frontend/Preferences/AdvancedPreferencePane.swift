import AppleAPI
import SwiftUI

struct AdvancedPreferencePane: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("dataSource") var dataSource: DataSource = .xcodeReleases
    @AppStorage("downloader") var downloader: Downloader = .aria2
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Data Source")) {
                VStack(alignment: .leading) {
                    Picker("Data Source", selection: $dataSource) {
                        ForEach(DataSource.allCases) { dataSource in
                            Text(dataSource.description)
                                .tag(dataSource)
                        }
                    }
                    .labelsHidden()
                    
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
                    
                    AttributedText(downloaderFootnote)
                }
                
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            
            GroupBox(label: Text("Privileged Helper")) {
                VStack(alignment: .leading, spacing: 8) {
                    switch appState.helperInstallState {
                    case .unknown:
                        ProgressView()
                            .scaleEffect(0.5, anchor: .center)
                    case .installed:
                        Text("Helper is installed")
                    case .notInstalled:
                        HStack {
                            Text("Helper is not installed")
                            Button("Install helper") {
                                appState.installHelperIfNecessary()
                            }
                        }
                    }
                    
                    Text("Xcodes uses a separate privileged helper to perform tasks as root. These are things that would require sudo on the command line, including post-install steps and switching Xcode versions with xcode-select.\n\nYou'll be prompted for your macOS account password to install it.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
        .frame(width: 400)
    }
    
    private var dataSourceFootnote: NSAttributedString {
        let string = """
        The Apple data source scrapes the Apple Developer website. It will always show the latest releases that are available, but is more fragile.

        Xcode Releases is an unofficial list of Xcode releases. It's provided as well-formed data, contains extra information that is not readily available from Apple, and is less likely to break if Apple redesigns their developer website.
        """
        let attributedString = NSMutableAttributedString(
            string: string, 
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .footnote, options: [:]),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributedString.addAttribute(.link, value: URL(string: "https://xcodereleases.com")!, range: NSRange(string.range(of: "Xcode Releases")!, in: string))
        return attributedString
    }
    
    private var downloaderFootnote: NSAttributedString {
        let string = """
        aria2 uses up to 16 connections to download Xcode 3-5x faster than URLSession. It's bundled as an executable along with its source code within Xcodes to comply with its GPLv2 license.

        URLSession is the default Apple API for making URL requests.
        """
        let attributedString = NSMutableAttributedString(
            string: string, 
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .footnote, options: [:]),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributedString.addAttribute(.link, value: URL(string: "https://github.com/aria2/aria2")!, range: NSRange(string.range(of: "aria2")!, in: string))
        return attributedString
    }
}

struct AdvancedPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AdvancedPreferencePane()
                .environmentObject(AppState())
        }
    }
}

// A group style for the preferences
struct PreferencesGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 20) {
            HStack {
                Spacer()
                configuration.label
            }
            .frame(width: 120)
            
            VStack(alignment: .leading) {
                configuration.content
            }
        }
    }
}
