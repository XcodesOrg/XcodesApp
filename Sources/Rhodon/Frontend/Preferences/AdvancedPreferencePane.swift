import AppleAPI
import Path
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedPreferencePane: View {
    @SwiftUI.Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Install Directory")) {
                VStack(alignment: .leading) {
                    HStack(alignment: .top, spacing: 5) {
                        Text(appState.installPath).font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                        Button(action: { appState.reveal(path: appState.installPath) }, label: {
                            Image(systemName: "arrow.right.circle.fill")
                        })
                        .buttonStyle(PlainButtonStyle())
                        .help("Reveal in Finder")
                        .fixedSize()
                    }
                    Button("Change") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.allowedContentTypes = [.folder]
                        panel.directoryURL = URL(fileURLWithPath: appState.installPath)

                        if panel.runModal() == .OK {
                            guard let pathURL = panel.url, let path = Path(url: pathURL) else { return }
                            appState.installPath = path.string
                        }
                    }
                    .disabled(appState.disableInstallPathChange)
                    Text(
                        // swiftlint:disable:next line_length
                        "Rhodon searches and installs to a single directory. By default (and recommended) is to keep this /Applications. Any changes to where Xcode is stored may result in other apps/services to stop working. "
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())

            GroupBox(label: Text("Local Cache Path")) {
                VStack(alignment: .leading) {
                    HStack(alignment: .top, spacing: 5) {
                        Text(appState.localPath).font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                        Button(action: { appState.reveal(path: appState.localPath) }, label: {
                            Image(systemName: "arrow.right.circle.fill")
                        })
                        .buttonStyle(PlainButtonStyle())
                        .help("Reveal in Finder")
                        .fixedSize()
                    }
                    Button("Change") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.allowedContentTypes = [.folder]
                        panel.directoryURL = URL(fileURLWithPath: appState.localPath)

                        if panel.runModal() == .OK {
                            guard let pathURL = panel.url, let path = Path(url: pathURL) else { return }
                            appState.localPath = path.string
                        }
                    }
                    .disabled(appState.disableLocalPathChange)
                    Text("Rhodon caches available Xcode versions and temporary downloads new versions to a directory")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())

            GroupBox(label: Text("Active/Select")) {
                VStack(alignment: .leading) {
                    Picker(selection: $appState.onSelectActionType) {
                        Text(SelectedActionType.none.description)
                            .tag(SelectedActionType.none)
                        Text(SelectedActionType.rename.description)
                            .tag(SelectedActionType.rename)
                    } label: {
                        Text(verbatim: "OnSelect")
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                    .disabled(appState.onSelectActionTypeDisabled)

                    Text(appState.onSelectActionType.detailedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                        .frame(height: 20)

                    Toggle("Automatically create symbolic link to Xcode.app", isOn: $appState.createSymLinkOnSelect)
                        .disabled(appState.createSymLinkOnSelectDisabled)
                    Text(
                        // swiftlint:disable:next line_length
                        "When making an Xcode version Active/Selected, try and create a symbolic link named Xcode.app in the installation directory"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())

            if Hardware.isAppleSilicon() {
                GroupBox(label: Text("Apple Silicon")) {
                    Toggle("Show Open In Rosetta option", isOn: $appState.showOpenInRosettaOption)
                        .disabled(appState.createSymLinkOnSelectDisabled)
                    Text(
                        // swiftlint:disable:next line_length
                        "Open in Rosetta option will show where other \"Open\" functions are available. Note: This will only show for Apple Silicon machines."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .groupBoxStyle(PreferencesGroupBoxStyle())
            }

            GroupBox(label: Text("Privileged Helper")) {
                VStack(alignment: .leading, spacing: 8) {
                    switch appState.helperInstallState {
                    case .unknown:
                        ProgressView()
                            .scaleEffect(0.5, anchor: .center)
                    case .installed:
                        Text("Helper is installed")
                    case .notInstalled:
                        VStack(alignment: .leading) {
                            Button("Install helper") {
                                appState.installHelperIfNecessary()
                            }
                            Text("Helper is not installed")
                                .font(.footnote)
                        }
                    }

                    Text(
                        // swiftlint:disable:next line_length
                        "Rhodon uses a separate privileged helper to perform tasks as root. These are things that would require sudo on the command line, including post-install steps and switching Xcode versions with xcode-select.\n\nYou'll be prompted for your macOS account password to install it."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
            }
            .groupBoxStyle(PreferencesGroupBoxStyle())
        }
    }
}

struct AdvancedPreferencePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AdvancedPreferencePane()
                .environment(AppState())
                .frame(maxWidth: 600)
        }
        .frame(width: 600, height: 700, alignment: .center)
    }
}

/// A group style for the preferences
struct PreferencesGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 20) {
            configuration.label
                .frame(width: 180, alignment: .trailing)

            VStack(alignment: .leading) {
                configuration.content
            }
        }
    }
}
