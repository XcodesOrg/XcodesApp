import AppleAPI
import Path
import SwiftUI

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
                    .disabled(appState.disableUnxipExperiment)
                    Text("FasterUnxipDescription")
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
                .environmentObject(AppState())
                .frame(maxWidth: 600)
        }
    }
}
