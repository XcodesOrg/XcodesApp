import Path
import SwiftUI
import Version
import XcodesKit

struct XcodeListViewRow: View {
    let xcode: Xcode
    let selected: Bool
    let appState: AppState
    let latestReleaseForSelectedPrerelease: Xcode?

    init(xcode: Xcode, selected: Bool, appState: AppState, latestReleaseForSelectedPrerelease: Xcode? = nil) {
        self.xcode = xcode
        self.selected = selected
        self.appState = appState
        self.latestReleaseForSelectedPrerelease = latestReleaseForSelectedPrerelease
    }

    var body: some View {
        HStack {
            appIconView(for: xcode)

            VStack(alignment: .leading) {
                HStack {
                    Text(verbatim: "\(xcode.description) \(xcode.version.buildMetadataIdentifiersDisplay)")
                        .font(.body)

                    if !xcode.identicalBuildsForCurrentVariant.isEmpty {
                        Image(systemName: "square.fill.on.square.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibility(label: Text("IdenticalBuilds"))
                            .accessibility(value: Text(xcode.identicalBuildsForCurrentVariant.map(\.version.appleDescription).joined(separator: ", ")))
                            .help("IdenticalBuilds.help")
                    }
                    
                    if xcode.architectures?.isAppleSilicon ?? false {
                        Image(systemName: "m4.button.horizontal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibility(label: Text("Apple Silicon"))
                            .help("Apple Silicon")
                    }
                }

                if case let .installed(path) = xcode.installState {
                    Text(verbatim: path.string)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            selectControl(for: xcode)
                .padding(.trailing, 16)
            installControl(for: xcode)
        }
        .padding(.vertical, 4)
        .contextMenu {
            switch xcode.installState {
            case .notInstalled:
                InstallButton(xcode: xcode)
            case .installing:
                CancelInstallButton(xcode: xcode)
            case let .installed(path):
                SelectButton(xcode: xcode)
                OpenButton(xcode: xcode)
                RevealButton(xcode: xcode)
                CopyPathButton(xcode: xcode)
                CreateSymbolicLinkButton(xcode: xcode)
                if xcode.version.isPrerelease {
                    CreateSymbolicBetaLinkButton(xcode: xcode)
                }
                Divider()
                UninstallButton(xcode: xcode)

                #if DEBUG
                    Divider()
                    Button("Perform post-install steps") {
                        appState.performPostInstallSteps(for: InstalledXcode(
                            path: path,
                            contentsAtPath: { path in Current.files.contents(atPath: path) },
                            loadArchitectures: Current.shell.archs
                        )!) as Void
                    }
                #endif
            }
        }
    }

    @ViewBuilder
    func appIconView(for xcode: Xcode) -> some View {
        if let icon = xcode.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image(xcode.version.isPrerelease ? "xcode-beta" : "xcode")
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(0.2)
        }
    }

    @ViewBuilder
    private func selectControl(for xcode: Xcode) -> some View {
        if xcode.installState.installed {
            if let latestReleaseForSelectedPrerelease, xcode.selected {
                switch latestReleaseForSelectedPrerelease.installState {
                case .installed:
                    Button(action: { appState.select(xcode: latestReleaseForSelectedPrerelease) }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(staleSelectedHelpText)
                case .notInstalled:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.yellow)
                        .help(staleSelectedHelpText)
                case .installing:
                    EmptyView()
                }
            } else if xcode.selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("ActiveVersionDescription")
            } else {
                Button(action: { appState.select(xcode: xcode) }) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("MakeActiveVersionDescription")
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func installControl(for xcode: Xcode) -> some View {
        if let latestReleaseForSelectedPrerelease,
           xcode.selected,
           latestReleaseForSelectedPrerelease.installState == .notInstalled {
            InstallButton(xcode: latestReleaseForSelectedPrerelease)
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
        } else {
            installStateControl(for: xcode)
        }
    }

    @ViewBuilder
    private func installStateControl(for xcode: Xcode) -> some View {
        switch xcode.installState {
        case .installed:
            Button("Open") { appState.open(xcode: xcode) }
                .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: selected))
                .help("OpenDescription")
        case .notInstalled:
            InstallButton(xcode: xcode)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
        case let .installing(installationStep):
            InstallationStepRowView(
                installationStep: installationStep,
                highlighted: selected,
                cancel: { appState.presentedAlert = .cancelInstall(xcode: xcode) }
            )
        }
    }

    private var staleSelectedHelpText: Text {
        let selectedVersion = xcode.version.appleDescription
        let latestVersion = latestReleaseForSelectedPrerelease?.version.appleDescription ?? ""

        switch latestReleaseForSelectedPrerelease?.installState {
        case .installed:
            return Text(verbatim: "\(selectedVersion) selected, \(latestVersion) available. Click to select \(latestVersion).")
        case .notInstalled:
            return Text(verbatim: "\(selectedVersion) selected, \(latestVersion) available. Install \(latestVersion) to select it.")
        case .installing, .none:
            return Text("ActiveVersionDescription")
        }
    }
}

struct XcodeListViewRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            XcodeListViewRow(
                xcode: Xcode(version: Version("12.3.0")!, installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: true, icon: nil),
                selected: false,
                appState: AppState()
            )

            XcodeListViewRow(
                xcode: Xcode(version: Version("12.2.0")!, installState: .notInstalled, selected: false, icon: nil),
                selected: false,
                appState: AppState()
            )

            XcodeListViewRow(
                xcode: Xcode(version: Version("12.1.0")!, installState: .installing(.downloading(progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40 })), selected: false, icon: nil),
                selected: false,
                appState: AppState()
            )

            XcodeListViewRow(
                xcode: Xcode(version: Version("12.0.0")!, installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: false, icon: nil),
                selected: false,
                appState: AppState()
            )

            XcodeListViewRow(
                xcode: Xcode(version: Version("12.0.0+1234A")!, installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: false, icon: nil),
                selected: false,
                appState: AppState()
            )

            XcodeListViewRow(
                xcode: Xcode(version: Version("12.0.0+1234A")!, identicalBuilds: [XcodeID(version: Version("12.0.0-RC+1234A")!)], installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: false, icon: nil),
                selected: false,
                appState: AppState()
            )
        }
    }
}
