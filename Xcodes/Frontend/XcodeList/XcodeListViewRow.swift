import Path
import SwiftUI
import Version

struct XcodeListViewRow: View {
    let xcode: Xcode
    let selected: Bool
    let appState: AppState

    var body: some View {
        HStack {
            appIconView(for: xcode)

            VStack(alignment: .leading) {
                HStack {
                    Text(verbatim: "\(xcode.description) \(xcode.version.buildMetadataIdentifiersDisplay)")
                        .font(.body)

                    if !xcode.identicalBuilds.isEmpty {
                        Image(systemName: "square.fill.on.square.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibility(label: Text("IdenticalBuilds"))
                            .accessibility(value: Text(xcode.identicalBuilds.map(\.appleDescription).joined(separator: ", ")))
                            .help("IdenticalBuilds.help")
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
                        appState.performPostInstallSteps(for: InstalledXcode(path: path)!) as Void
                    }
                #endif
            }
        }
    }

    @ViewBuilder
    func appIconView(for xcode: Xcode) -> some View {
        if let icon = xcode.icon {
            Image(nsImage: icon)
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
            if xcode.selected {
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
        switch xcode.installState {
        case .installed:
            Button("Open") { appState.open(xcode: xcode) }
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: selected))
                .help("OpenDescription")
        case .notInstalled:
            InstallButton(xcode: xcode)
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
        case let .installing(installationStep):
            InstallationStepRowView(
                installationStep: installationStep,
                highlighted: selected,
                cancel: { appState.presentedAlert = .cancelInstall(xcode: xcode) }
            )
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
                xcode: Xcode(version: Version("12.0.0+1234A")!, identicalBuilds: [Version("12.0.0-RC+1234A")!], installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: false, icon: nil),
                selected: false,
                appState: AppState()
            )
        }
    }
}
