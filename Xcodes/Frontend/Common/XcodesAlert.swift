import Foundation
import SwiftUI
import XcodesKit

enum XcodesAlert: Identifiable {
    case cancelInstall(xcode: Xcode)
    case cancelRuntimeInstall(runtime: DownloadableRuntime)
    case privilegedHelper
    case postInstallFailed(xcode: InstalledXcode)
    case unauthenticatedDataSource
    case generic(title: String, message: String)
    case checkMinSupportedVersion(xcode: AvailableXcode, macOS: String)
    case unauthenticated

    var id: Int {
        switch self {
        case .cancelInstall: return 1
        case .privilegedHelper: return 2
        case .postInstallFailed: return 10
        case .unauthenticatedDataSource: return 7
        case .generic: return 3
        case .checkMinSupportedVersion: return 4
        case .cancelRuntimeInstall: return 5
        case .unauthenticated: return 6
        }
    }
}

// Splitting out alerts that are shown on the preference screen as by default we are showing on the MainWindow()
// and users awkwardly switch screens, sometimes losing the preference screen
enum XcodesPreferencesAlert: Identifiable {
    case deletePlatform(runtime: DownloadableRuntime)
    case generic(title: String, message: String)
    
    var id: Int {
        switch self {
        case .deletePlatform: return 1
        case .generic: return 2
        }
    }
}

struct HelperFileOperationError: LocalizedError {
    let underlyingError: Error
    let command: String
    var errorDescription: String? { underlyingError.localizedDescription }
}

/// The command is displayed and copied only; Xcodes never executes it.
struct HelperRecovery {
    let title: String
    let message: String
    let command: String

    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func selectCommand(path: String) -> String {
        "sudo /usr/bin/xcode-select --switch " + quote(path)
    }

    static func moveCommand(source: String, destination: String) -> String {
        // Refuse to overwrite an existing app, including a dangling symlink.
        let destination = quote(destination)
        return "[ ! -e " + destination + " ] && [ ! -L " + destination + " ] && sudo /bin/mv " + quote(source) + " " + destination
    }

    static func symlinkCommand(source: String, destination: String) -> String {
        let destination = quote(destination)
        return "([ ! -e " + destination + " ] || [ -L " + destination + " ]) && sudo /bin/ln -sfn " + quote(source) + " " + destination
    }
}

struct HelperRecoveryView: View {
    @EnvironmentObject var appState: AppState
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var copied = false
    let recovery: HelperRecovery

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: recovery.title).font(.headline)
            Text(verbatim: recovery.message).textSelection(.enabled)
            Text("HelperRecovery.Explanation")
            ScrollView {
                Text(verbatim: recovery.command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 180)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
            HStack {
                if #available(macOS 14, *) {
                    HelperSettingsButton {
                        appState.showHelperSettings = true
                        dismiss()
                    }
                } else {
                    Button("HelperRecovery.OpenSettings") {
                        appState.showHelperSettings = true
                        dismiss()
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
                Button(copied ? "HelperRecovery.Copied" : "HelperRecovery.CopyCommand") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recovery.command, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}

@available(macOS 14, *)
private struct HelperSettingsButton: View {
    @SwiftUI.Environment(\.openSettings) private var openSettings
    let prepare: () -> Void

    var body: some View {
        Button("HelperRecovery.OpenSettings") {
            prepare()
            openSettings()
        }
    }
}
