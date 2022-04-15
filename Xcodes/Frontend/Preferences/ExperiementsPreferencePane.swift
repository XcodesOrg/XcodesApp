import AppleAPI
import SwiftUI
import Path

struct ExperimentsPreferencePane: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("FasterUnxip")) {
                VStack(alignment: .leading) {
                    Toggle(
                        "UseUnxipExperiment",
                        isOn: $appState.unxipExperiment
                    )
                    AttributedText(unxipFootnote)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
            
            Divider()
        }
        .frame(width: 500)
    }
    
    private var unxipFootnote: NSAttributedString {
        let string = localizeString("FasterUnxipDescription")
        let attributedString = NSMutableAttributedString(
            string: string,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .footnote, options: [:]),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributedString.addAttribute(.link, value: URL(string: "https://twitter.com/_saagarjha")!, range: NSRange(string.range(of: "@_saagarjha")!, in: string))
        attributedString.addAttribute(.link, value: URL(string: "https://github.com/saagarjha/unxip")!, range: NSRange(string.range(of: "https://github.com/saagarjha/unxip")!, in: string))
        return attributedString
    }
}

struct ExperimentsPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ExperimentsPreferencePane()
                .environmentObject(AppState())
        }
    }
}
