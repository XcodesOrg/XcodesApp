import Path
import SwiftUI
import Version
import XcodesKit

struct XcodeListViewRow: View {
    enum Style {
        /// Standalone rows include the Xcode icon.
        case flat
        /// Rows under a version group rely on the group's icon.
        case grouped
    }

    let xcode: Xcode
    let selected: Bool
    @ObservedObject var appState: AppState
    let latestReleaseForSelectedPrerelease: Xcode?
    let style: Style
    let isLatestRelease: Bool

    init(xcode: Xcode, selected: Bool, appState: AppState, latestReleaseForSelectedPrerelease: Xcode? = nil, style: Style = .flat, isLatestRelease: Bool = false) {
        self.xcode = xcode
        self.selected = selected
        self.appState = appState
        self.latestReleaseForSelectedPrerelease = latestReleaseForSelectedPrerelease
        self.style = style
        self.isLatestRelease = isLatestRelease
    }

    private var title: String {
        // Tags carry the prerelease name in either layout; keep it in the title when tags are hidden.
        guard appState.showTags else { return xcode.description }
        let version = xcode.version
        return Version(major: version.major, minor: version.minor, patch: version.patch).appleDescription
    }

    /// Secondary line: the build and the install path, when present.
    private var caption: String? {
        var parts: [String] = xcode.version.buildMetadataIdentifiers
        if case let .installed(path) = xcode.installState {
            parts.append(path.string)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            // Rows under a version group rely on the group's icon
            if style == .flat {
                appIconView(for: xcode)
            }

            VStack(alignment: .leading) {
                // The version must never truncate; when space is tight, drop the small symbols first
                ViewThatFits(in: .horizontal) {
                    titleLine(showsSymbols: true)
                    titleLine(showsSymbols: false)
                }

                if let caption {
                    Text(verbatim: caption)
                        .font(.caption)
                        // A hierarchical style stays legible on the selection highlight, unlike Color.secondary
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            selectControl(for: xcode)
                .padding(.trailing, 16)
            installControl(for: xcode)
                // Same column width as the Install/Open buttons, so the progress ring lines up with them
                .frame(minWidth: 67)
        }
        .padding(.vertical, 4)
        .contextMenu {
            switch xcode.installState {
            case .notInstalled:
                InstallButton(xcode: xcode)
            case .installing:
                CancelInstallButton(xcode: xcode)
            case .uninstalling:
                EmptyView()
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

    private func titleLine(showsSymbols: Bool) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.body)
                .fixedSize()
                .treeGuideTitle()

            if appState.showTags {
                if let prereleaseTag = ReleaseTagView(prereleaseOf: xcode.version) {
                    prereleaseTag
                }
                if isLatestRelease {
                    ReleaseTagView.latest
                }
                if xcode.selected {
                    ReleaseTagView.active
                }
            }

            if showsSymbols {
                if !xcode.identicalBuildsForCurrentVariant.isEmpty {
                    Image(systemName: "square.fill.on.square.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibility(label: Text("IdenticalBuilds"))
                        .accessibility(value: Text(xcode.identicalBuildsForCurrentVariant.map(\.version.appleDescription).joined(separator: ", ")))
                        .help("IdenticalBuilds.help")
                }

                if xcode.architectures?.isAppleSilicon ?? false {
                    Image(systemName: "m4.button.horizontal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibility(label: Text("Apple Silicon"))
                        .help("Apple Silicon")
                }
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
                .opacity(0.5)
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
                case .installing, .uninstalling:
                    EmptyView()
                }
            } else if xcode.selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("ActiveVersionDescription")
            } else {
                Button(action: { appState.select(xcode: xcode) }) {
                    // Installed but not active: green outline; the active Xcode gets the filled check
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
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
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: false))
                .help("OpenDescription")
        case .notInstalled:
            InstallButton(xcode: xcode)
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
        case let .installing(installationStep):
            InstallationStepRowView(
                installationStep: installationStep,
                highlighted: false,
                cancel: { appState.presentedAlert = .cancelInstall(xcode: xcode) }
            )
        case .uninstalling:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Uninstalling")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        case .installing, .uninstalling, .none:
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
