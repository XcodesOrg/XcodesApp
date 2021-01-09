import SwiftUI

// MARK: - CommandMenu

struct XcodeCommands: Commands {
    // CommandMenus don't participate in the environment hierarchy, so we need to shuffle AppState along to the individual Commands manually.
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
                
                Divider()
                
                UninstallCommand()
            }
            .environmentObject(appState)
        }
    }
}

// MARK: - Buttons
// These are used for both context menus and commands

struct InstallButton: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode?
    
    var body: some View {
        Button(action: install) {
            Text("Install")
                .help("Install")
        }
    }
    
    private func install() {
        guard let xcode = xcode else { return }
        appState.install(id: xcode.id)
    }
}

struct CancelInstallButton: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode?
    
    var body: some View {
        Button(action: cancelInstall) {
            Text("Cancel")
                .help("Stop installation")
        }
    }
    
    private func cancelInstall() {
        guard let xcode = xcode else { return }
        appState.xcodeBeingConfirmedForInstallCancellation = xcode
    }
}

struct SelectButton: View {
    @EnvironmentObject var appState: AppState
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
        guard let xcode = xcode else { return }
        appState.select(id: xcode.id)
    }
}

struct OpenButton: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode?
    
    var body: some View {
        Button(action: open) {
            Text("Open")
        }
        .help("Open")
    }
    
    private func open() {
        guard let xcode = xcode else { return }
        appState.open(id: xcode.id)
    }
}

struct UninstallButton: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode?
    
    var body: some View {
        Button(action: {
            appState.xcodeBeingConfirmedForUninstallation = xcode
        }) {
            Text("Uninstall")
        }
        .foregroundColor(.red)
        .help("Uninstall")
    }
}

struct RevealButton: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode?
    
    var body: some View {
        Button(action: reveal) {
            Text("Reveal in Finder")
        }
        .help("Reveal in Finder")
    }
    
    private func reveal() {
        guard let xcode = xcode else { return }
        appState.reveal(id: xcode.id)
    }
}

struct CopyPathButton: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode?
    
    var body: some View {
        Button(action: copyPath) {
            Text("Copy Path")
        }
        .help("Copy path")
    }
    
    private func copyPath() {
        guard let xcode = xcode else { return }
        appState.copyPath(id: xcode.id)
    }
}

// MARK: - Commands

struct InstallCommand: View {
    @EnvironmentObject var appState: AppState
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
    @EnvironmentObject var appState: AppState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        SelectButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct OpenCommand: View {
    @EnvironmentObject var appState: AppState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        OpenButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut(KeyboardShortcut(.downArrow, modifiers: .command))
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct RevealCommand: View {
    @EnvironmentObject var appState: AppState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        RevealButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct CopyPathCommand: View {
    @EnvironmentObject var appState: AppState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?

    var body: some View {
        CopyPathButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}

struct UninstallCommand: View {
    @EnvironmentObject var appState: AppState
    @FocusedValue(\.selectedXcode) private var selectedXcode: SelectedXcode?
    
    var body: some View {
        UninstallButton(xcode: selectedXcode.unwrapped)
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(selectedXcode.unwrapped?.installState.installed != true)
    }
}
