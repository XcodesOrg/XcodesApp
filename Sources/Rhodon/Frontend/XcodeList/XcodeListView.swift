import Path
import SwiftUI
import Version
import RhodonKit

struct XcodeListView: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @Binding var selectedXcodeID: Xcode.ID?
    private let searchText: String
    private let category: XcodeListCategory
    private let architecture: XcodeListArchitecture
    private let isInstalledOnly: Bool
    @AppStorage(PreferenceKey.allowedMajorVersions.rawValue) private var allowedMajorVersions = Int.max

    init(
        selectedXcodeID: Binding<Xcode.ID?>,
        searchText: String,
        category: XcodeListCategory,
        isInstalledOnly: Bool,
        architecture: XcodeListArchitecture
    ) {
        _selectedXcodeID = selectedXcodeID
        self.searchText = searchText
        self.category = category
        self.isInstalledOnly = isInstalledOnly
        self.architecture = architecture
    }

    var visibleRhodon: [Xcode] {
        var rhodon: [Xcode] = switch category {
        case .all:
            appState.allRhodon
        case .release:
            appState.allRhodon.filter(\.version.isNotPrerelease)
        case .beta:
            appState.allRhodon.filter(\.version.isPrerelease)
        }

        if architecture == .appleSilicon {
            rhodon = rhodon.filter { $0.architectures == [.arm64] }
        }

        let latestMajor = rhodon.sorted(\.version)
            .filter(\.version.isNotPrerelease)
            .last?
            .version
            .major

        rhodon = rhodon.filter {
            if
                $0.installState.notInstalled,
                let latestMajor,
                $0.version.major < (latestMajor - min(latestMajor, allowedMajorVersions)) {
                return false
            }

            return true
        }

        if !searchText.isEmpty {
            rhodon = rhodon.filter { $0.description.contains(searchText) }
        }

        if isInstalledOnly {
            rhodon = rhodon.filter(\.installState.installed)
        }

        return rhodon
    }

    var body: some View {
        List(visibleRhodon, selection: $selectedXcodeID) { xcode in
            XcodeListViewRow(xcode: xcode, selected: selectedXcodeID == xcode.id, appState: appState)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlatformsPocket()
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }
}

struct PlatformsPocket: View {
    @SwiftUI.Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: {
            openWindow(id: "platforms")
        }, label: {
            if #available(macOS 26.0, *) {
                platformsLabel
                    .glassEffect(in: .rect(cornerRadius: 8, style: .continuous))
            } else {
                platformsLabel
                    .background(.quaternary.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        })
        .buttonStyle(.plain)
    }

    var platformsLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.3.layers.3d")
                .font(.title3.weight(.medium))
            Text("Installed Platforms")
            Spacer()
        }
        .font(.body.weight(.medium))
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

struct XcodeListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            XcodeListView(
                selectedXcodeID: .constant(nil),
                searchText: "",
                category: .all,
                isInstalledOnly: false,
                architecture: .appleSilicon
            )
            .environment({ () -> AppState in
                let appState = AppState()
                appState.allRhodon = [
                    Xcode(
                        version: Version("12.0.0+1234A")!,
                        identicalBuilds: [
                            XcodeID(version: Version("12.0.0+1234A")!),
                            XcodeID(version: Version("12.0.0-RC+1234A")!)
                        ],
                        installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                        selected: false,
                        icon: nil
                    ),
                    Xcode(
                        version: Version("12.3.0")!,
                        installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                        selected: true,
                        icon: nil
                    ),
                    Xcode(version: Version("12.2.0")!, installState: .notInstalled, selected: false, icon: nil),
                    Xcode(
                        version: Version("12.1.0")!,
                        installState: .installing(.downloading(progress: configure(Progress(totalUnitCount: 100)) {
                            $0.completedUnitCount = 40
                        })),
                        selected: false,
                        icon: nil
                    ),
                    Xcode(
                        version: Version("12.0.0")!,
                        installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                        selected: false,
                        icon: nil
                    ),
                    Xcode(version: Version("10.1.0")!, installState: .notInstalled, selected: false, icon: nil),
                    Xcode(
                        version: Version("10.0.0")!,
                        installState: .installed(Path("/Applications/Xcode-10.0.0.app")!),
                        selected: false,
                        icon: nil
                    ),
                    Xcode(version: Version("9.0.0")!, installState: .notInstalled, selected: false, icon: nil)
                ]
                return appState
            }())
        }
        .previewLayout(.sizeThatFits)
    }
}
