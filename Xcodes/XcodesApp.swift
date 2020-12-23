import SwiftUI

@main
struct XcodesApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        Group {
            WindowGroup("Xcodes") {
                XcodeListView()
                    .environmentObject(appState)
            }
        }
    }
}
