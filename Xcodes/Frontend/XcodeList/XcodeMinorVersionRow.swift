import SwiftUI
import Version
import Path

struct XcodeMinorVersionRow: View {
    let minorVersionGroup: XcodeMinorVersionGroup
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let appState: AppState

    var body: some View {
        HStack {
            Button(action: onToggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    minorVersionIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Xcode \(minorVersionGroup.displayName)")
                            .font(.callout.weight(.medium))

                        if let latestRelease = minorVersionGroup.latestRelease {
                            Text("Latest: \(latestRelease.description)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            selectControl()
                .padding(.trailing, 16)
            installControl()
        }
        .padding(.vertical, 6)
        .padding(.leading, 20)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    var minorVersionIcon: some View {
        if let latestRelease = minorVersionGroup.latestRelease {
            if let icon = latestRelease.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image("xcode")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .opacity(0.6)
            }
        } else {
            Image("xcode-beta")
                .resizable()
                .frame(width: 28, height: 28)
                .opacity(0.6)
        }
    }

    @ViewBuilder
    func selectControl() -> some View {
        if let selectedVersion = minorVersionGroup.selectedVersion {
            if selectedVersion.selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("ActiveVersionDescription")
            } else {
                EmptyView()
            }
        } else if minorVersionGroup.hasInstalled {
            EmptyView()
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    func installControl() -> some View {
        if minorVersionGroup.hasInstalling {
            if let installingVersion = minorVersionGroup.versions.first(where: { $0.installState.installing }) {
                if case let .installing(installationStep) = installingVersion.installState {
                    InstallationStepRowView(
                        installationStep: installationStep,
                        highlighted: false,
                        cancel: { appState.presentedAlert = .cancelInstall(xcode: installingVersion) }
                    )
                }
            }
        } else if let latestRelease = minorVersionGroup.latestRelease {
            switch latestRelease.installState {
            case .installed:
                Button("Open") { appState.open(xcode: latestRelease) }
                    .textCase(.uppercase)
                    .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: false))
                    .help("OpenDescription")
            case .notInstalled:
                Button("Install Latest") {
                    appState.checkMinVersionAndInstall(id: latestRelease.id)
                }
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
                .help("InstallLatestVersionDescription")
            case .installing:
                EmptyView()
            }
        }
    }
}

struct XcodeMinorVersionRow_Previews: PreviewProvider {
    static var previews: some View {
        let sampleXcodes = [
            Xcode(version: Version("16.4.0")!, installState: .installed(Path("/Applications/Xcode-16.4.0.app")!), selected: true, icon: nil),
            Xcode(version: Version("16.4.1")!, installState: .notInstalled, selected: false, icon: nil),
        ]

        let minorVersionGroup = XcodeMinorVersionGroup(
            majorVersion: 16,
            minorVersion: 4,
            versions: sampleXcodes,
            isExpanded: false
        )

        XcodeMinorVersionRow(
            minorVersionGroup: minorVersionGroup,
            isExpanded: false,
            onToggleExpanded: {},
            appState: AppState()
        )
        .previewLayout(.sizeThatFits)
    }
}