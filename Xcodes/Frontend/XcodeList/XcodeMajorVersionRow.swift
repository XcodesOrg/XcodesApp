import SwiftUI
import Version
import Path

struct XcodeMajorVersionRow: View {
    let majorVersionGroup: XcodeMajorVersionGroup
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

                    majorVersionIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Xcode \(majorVersionGroup.displayName)")
                            .font(.body.weight(.medium))

                        if let latestRelease = majorVersionGroup.latestRelease {
                            Text("Latest: \(latestRelease.description)")
                                .font(.caption)
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
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    var majorVersionIcon: some View {
        if let latestRelease = majorVersionGroup.latestRelease {
            if let icon = latestRelease.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image("xcode")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .opacity(0.7)
            }
        } else {
            Image("xcode-beta")
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(0.7)
        }
    }

    @ViewBuilder
    func selectControl() -> some View {
        if let selectedVersion = majorVersionGroup.selectedVersion {
            if selectedVersion.selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("ActiveVersionDescription")
            } else {
                EmptyView()
            }
        } else if majorVersionGroup.hasInstalled {
            EmptyView()
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    func installControl() -> some View {
        if majorVersionGroup.hasInstalling {
            if let installingVersion = majorVersionGroup.versions.first(where: { $0.installState.installing }) {
                if case let .installing(installationStep) = installingVersion.installState {
                    InstallationStepRowView(
                        installationStep: installationStep,
                        highlighted: false,
                        cancel: { appState.presentedAlert = .cancelInstall(xcode: installingVersion) }
                    )
                }
            }
        } else if let latestRelease = majorVersionGroup.latestRelease {
            switch latestRelease.installState {
            case .installed:
                Button("Open") { appState.open(xcode: latestRelease) }
                    .textCase(.uppercase)
                    .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: false))
                    .help("OpenDescription")
            case .notInstalled:
                Button("Install Latest Release") {
                    appState.checkMinVersionAndInstall(id: latestRelease.id)
                }
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
                .help("InstallLatestReleaseDescription")
            case .installing:
                EmptyView()
            }
        }
    }
}

struct XcodeMajorVersionRow_Previews: PreviewProvider {
    static var previews: some View {
        let sampleXcodes = [
            Xcode(version: Version("16.4.0")!, installState: .installed(Path("/Applications/Xcode-16.4.0.app")!), selected: true, icon: nil),
            Xcode(version: Version("16.3.0")!, installState: .notInstalled, selected: false, icon: nil),
            Xcode(version: Version("16.2.0")!, installState: .notInstalled, selected: false, icon: nil),
        ]

        let minorVersionGroups = [
            XcodeMinorVersionGroup(
                majorVersion: 16,
                minorVersion: 4,
                versions: [sampleXcodes[0]]
            ),
            XcodeMinorVersionGroup(
                majorVersion: 16,
                minorVersion: 3,
                versions: [sampleXcodes[1]]
            ),
            XcodeMinorVersionGroup(
                majorVersion: 16,
                minorVersion: 2,
                versions: [sampleXcodes[2]]
            )
        ]

        let majorVersionGroup = XcodeMajorVersionGroup(
            majorVersion: 16,
            minorVersionGroups: minorVersionGroups,
            isExpanded: false
        )

        XcodeMajorVersionRow(
            majorVersionGroup: majorVersionGroup,
            isExpanded: false,
            onToggleExpanded: {},
            appState: AppState()
        )
        .previewLayout(.sizeThatFits)
    }
}
