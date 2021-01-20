import AppleAPI
import Preferences
import Sparkle
import SwiftUI

extension Preferences.PaneIdentifier {
    static let updates = Self("updates")
}

struct UpdatesPreferencePane: View {
    @StateObject var updater = ObservableUpdater()
    
    var body: some View {
        Preferences.Container(contentWidth: 400.0) {
            Preferences.Section(title: "Updates") {
                VStack(alignment: .leading) {
                    Toggle(
                        "Automatically check for updates", 
                        isOn: $updater.automaticallyChecksForUpdates
                    )
                                        
                    Button("Check Now") {
                        SUUpdater.shared()?.checkForUpdates(nil)
                    }

                    Text("Last checked: \(lastUpdatedString)")
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var lastUpdatedString: String {
        if let lastUpdatedDate = updater.lastUpdateCheckDate {
            return Self.formatter.string(from: lastUpdatedDate)
        } else {
            return "Never"
        }
    }
    
    private static let formatter = configure(DateFormatter()) {
        $0.dateStyle = .medium
        $0.timeStyle = .medium
    }
}

class ObservableUpdater: ObservableObject {
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            SUUpdater.shared()?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?
    @Published var lastUpdateCheckDate: Date?
    private var lastUpdateCheckDateObservation: NSKeyValueObservation?
    
    
    init() {
        automaticallyChecksForUpdatesObservation = SUUpdater.shared()?.observe(
            \.automaticallyChecksForUpdates, 
            options: [.initial, .new, .old],
            changeHandler: { [unowned self] updater, change in
                guard change.newValue != change.oldValue else { return }
                self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            }
        )
        lastUpdateCheckDateObservation = SUUpdater.shared()?.observe(
            \.lastUpdateCheckDate, 
            options: [.initial, .new, .old],
            changeHandler: { [unowned self] updater, change in
                self.lastUpdateCheckDate = updater.lastUpdateCheckDate
            }
        )
    }
}

struct UpdatesPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UpdatesPreferencePane()
                .environmentObject(AppState())
        }
    }
}
