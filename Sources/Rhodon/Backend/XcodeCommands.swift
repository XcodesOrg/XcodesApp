import SwiftUI
import RhodonKit

// MARK: - CommandMenu

struct XcodeCommands: Commands {
    /// CommandMenus don't participate in the environment hierarchy, so we need to shuffle AppState along to the
    /// individual Commands manually.
    let appState: AppState

    var body: some Commands {
        CommandMenu("Xcode") {
            Group {
                InstallCommand()

                Divider()

                SelectCommand()
                OpenCommand()
                RevealCommand()
                CopyPathCommand()
                CreateSymbolicLinkCommand()

                Divider()

                UninstallCommand()
            }
            .environment(appState)
        }
    }
}

// MARK: - Buttons

// These are used for both context menus and commands

struct InstallButton: View {
    @SwiftUI.Environment(AppState.self) private var appState

    let xcode: Xcode?

    var body: some View {
        Button {
            install()
        } label: {
            Text("Install")
                .help("Install this version")
        }
    }

    private func install() {
        guard let xcode else { return }
        appState.checkMinVersionAndInstall(id: xcode.id)
    }
}

struct CancelInstallButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: cancelInstall) {
            Label("Cancel", systemImage: "xmark")
        }
        .help("Stop installation")
        .buttonStyle(.plain)
    }

    private func cancelInstall() {
        guard let xcode else { return }
        appState.presentedAlert = .cancelInstall(xcode: xcode)
    }
}

struct CancelRuntimeInstallButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let runtime: DownloadableRuntime?

    var body: some View {
        Button(action: cancelInstall) {
            Image(systemName: "xmark.circle.fill")
        }.help("Stop installation")
            .buttonStyle(.plain)
    }

    private func cancelInstall() {
        guard let runtime else { return }
        appState.presentedAlert = .cancelRuntimeInstall(runtime: runtime)
    }
}

struct SelectButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: select) {
            if xcode?.selected == true {
                Text("Active")
            } else {
                Text("Make active")
            }
        }
        .disabled(xcode?.selected != false)
        .help("Select")
    }

    private func select() {
        guard let xcode else { return }
        appState.select(xcode: xcode)
    }
}

struct OpenButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var openInRosetta: Bool {
        appState.showOpenInRosettaOption && Hardware.isAppleSilicon()
    }

    var body: some View {
        if openInRosetta {
            Menu("Open") {
                Button(action: open) {
                    Text("Open")
                }
                .help("Open")
                Button(action: open) {
                    Text("Open In Rosetta")
                }
                .help("Open In Rosetta")
            }
        } else {
            Button(action: open) {
                Text("Open")
            }
            .help("Open")
        }
    }

    private func open() {
        guard let xcode else { return }
        appState.open(xcode: xcode, openInRosetta: openInRosetta)
    }
}

struct UninstallButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: {
            appState.xcodeBeingConfirmedForUninstallation = xcode
        }, label: {
            Text("Uninstall")
        })
        .foregroundColor(.red)
        .help("Uninstall")
    }
}

struct RevealButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: reveal) {
            Text("Reveal in Finder")
        }
        .help("Reveal in Finder")
    }

    private func reveal() {
        guard let xcode else { return }
        appState.reveal(xcode.installedPath)
    }
}

struct CopyPathButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: copyPath) {
            Text("Copy Path")
        }
        .help("Copy Path")
    }

    private func copyPath() {
        guard let xcode else { return }
        appState.copyPath(xcode: xcode)
    }
}

struct CopyReleaseNoteButton: View {
    let url: URL?

    @SwiftUI.Environment(AppState.self) private var appState

    var body: some View {
        Button(action: copyReleaseNote) {
            Text("Copy URL")
        }
        .help("Copy URL")
    }

    private func copyReleaseNote() {
        guard let url else { return }
        appState.copyReleaseNote(from: url)
    }
}

struct CreateSymbolicLinkButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: createSymbolicLink) {
            Text("Create Symlink as Xcode.app")
        }
        .help("Create Symlink as Xcode.app")
    }

    private func createSymbolicLink() {
        guard let xcode else { return }
        appState.createSymbolicLink(xcode: xcode)
    }
}

struct DownloadRuntimeButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let runtime: DownloadableRuntime?

    var body: some View {
        Button(action: install) {
            Text("Install")
                .help("Install")
        }
    }

    private func install() {
        guard let runtime else { return }
        appState.downloadRuntime(runtime: runtime)
    }
}

struct CreateSymbolicBetaLinkButton: View {
    @SwiftUI.Environment(AppState.self) private var appState
    let xcode: Xcode?

    var body: some View {
        Button(action: createSymbolicBetaLink) {
            Text("Create Symlink as Xcode-Beta.app")
        }
        .help("Create Symlink as Xcode-Beta.app")
    }

    private func createSymbolicBetaLink() {
        guard let xcode else { return }
        appState.createSymbolicLink(xcode: xcode, isBeta: true)
    }
}

// MARK: - Commands

struct InstallCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        if selectedXcode.unwrapped?.installState.installing == true {
            CancelInstallButton(xcode: selectedXcode.unwrapped)
                .keyboardShortcut(".", modifiers: [.command])
        } else {
            InstallButton(xcode: selectedXcode.unwrapped)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(selectedXcode.unwrapped?.installState != .notInstalled)
        }
    }
}

struct SelectCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        SelectButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct OpenCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        OpenButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut(KeyboardShortcut(.downArrow, modifiers: .command))
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct RevealCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        RevealButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct CopyPathCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        CopyPathButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct UninstallCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        UninstallButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct CreateSymbolicLinkCommand: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        CreateSymbolicLinkButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}
