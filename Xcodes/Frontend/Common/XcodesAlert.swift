import Foundation
import SwiftUI
import XcodesKit

enum XcodesAlert: Identifiable {
    case cancelInstall(xcode: Xcode)
    case cancelRuntimeInstall(runtime: DownloadableRuntime)
    case privilegedHelper
    case generic(title: String, message: String)
    case checkMinSupportedVersion(xcode: AvailableXcode, macOS: String)
    case unauthenticated
    case deletePlatform(runtime: DownloadableRuntime)
    case noActiveXcode(runtime: DownloadableRuntime, xcode: Xcode?)

    var id: Int {
        switch self {
        case .cancelInstall: return 1
        case .privilegedHelper: return 2
        case .generic: return 3
        case .checkMinSupportedVersion: return 4
        case .cancelRuntimeInstall: return 5
        case .unauthenticated: return 6
        case .deletePlatform: return 8
        case .noActiveXcode: return 9
        }
    }
}

// Splitting out alerts that are shown on the preference screen as by default we are showing on the MainWindow()
// and users awkwardly switch screens, sometimes losing the preference screen
enum XcodesPreferencesAlert: Identifiable {
    case deletePlatform(runtime: DownloadableRuntime)
    case generic(title: String, message: String)
    case noActiveXcode(runtime: DownloadableRuntime, xcode: Xcode?)
    
    var id: Int {
        switch self {
        case .deletePlatform: return 1
        case .generic: return 2
        case .noActiveXcode: return 3
        }
    }
}

extension Alert {
    /// Removing a platform runs `simctl`, which only comes with Xcode. Offers to make the newest installed release active and retry.
    @MainActor
    static func noActiveXcode(appState: AppState, runtime: DownloadableRuntime, xcode: Xcode?, inSettings: Bool) -> Alert {
        let explanation = String(format: localizeString("Alert.NoActiveXcode.Message"), runtime.name, appState.selectedXcodePath ?? "–")
        guard let xcode else {
            return Alert(
                title: Text("Alert.NoActiveXcode.Title"),
                message: Text(verbatim: explanation + "\n\n" + localizeString("Alert.NoActiveXcode.NoneInstalled")),
                dismissButton: .default(Text("OK"))
            )
        }
        return Alert(
            title: Text("Alert.NoActiveXcode.Title"),
            message: Text(verbatim: explanation),
            primaryButton: .default(
                Text(String(format: localizeString("Alert.NoActiveXcode.PrimaryButton"), xcode.description)),
                action: { appState.selectXcodeAndDeleteRuntime(xcode: xcode, runtime: runtime, presentErrorInSettings: inSettings) }
            ),
            secondaryButton: .cancel(Text("Cancel"))
        )
    }
}
