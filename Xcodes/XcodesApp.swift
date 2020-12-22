import SwiftUI

@main
struct XcodesApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup("Xcodes") {
            XcodeListView()
                .environmentObject(appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
