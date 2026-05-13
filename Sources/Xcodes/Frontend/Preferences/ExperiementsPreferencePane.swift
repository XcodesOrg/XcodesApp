import AppleAPI
import Path
import SwiftUI

struct ExperimentsPreferencePane: View {
    @SwiftUI.Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Faster Unxip")) {
                VStack(alignment: .leading) {
                    Toggle(
                        "When unxipping, use experiment",
                        isOn: $appState.unxipExperiment
                    )
                    .disabled(appState.disableUnxipExperiment)
                    Text(
                        // swiftlint:disable:next line_length
                        "Thanks to [@_saagarjha](https://twitter.com/_saagarjha), this experiment can increase unxipping speed by up to 70% for some systems.\n\nMore information on how this is accomplished can be seen on the unxip repo - https://github.com/saagarjha/unxip"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
    }
}

struct ExperimentsPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ExperimentsPreferencePane()
                .environment(AppState())
                .frame(maxWidth: 600)
        }
    }
}
