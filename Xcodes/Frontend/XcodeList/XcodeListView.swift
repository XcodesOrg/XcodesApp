import Path
import SwiftUI
import Version
import XcodesKit

struct XcodeListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedXcodeID: Xcode.ID?
    private let searchText: String
    private let category: XcodeListCategory
    private let architecture: XcodeListArchitecture
    private let isInstalledOnly: Bool
    @AppStorage(PreferenceKey.allowedMajorVersions.rawValue) private var allowedMajorVersions = Int.max

    init(selectedXcodeID: Binding<Xcode.ID?>, searchText: String, category: XcodeListCategory, isInstalledOnly: Bool, architecture: XcodeListArchitecture) {
        self._selectedXcodeID = selectedXcodeID
        self.searchText = searchText
        self.category = category
        self.isInstalledOnly = isInstalledOnly
        self.architecture = architecture
    }
    
    private var visibleXcodes: [XcodeListEntry] {
        appState.allXcodes
            .enumerated()
            .map { XcodeListEntry(index: $0.offset, xcode: $0.element) }
            .applying(XcodeListFilters(
                versionFilter: category.versionFilter,
                architectureFilters: architecture.architectureFilters,
                allowedMajorVersions: allowedMajorVersions,
                searchText: searchText,
                installedOnly: isInstalledOnly
            ), item: \.listItem)
    }
    
    var body: some View {
        List(selection: $selectedXcodeID) {
            if appState.enableGroupedXcodeList {
                GroupedXcodeListContent(
                    xcodes: visibleXcodes,
                    selectedXcodeID: $selectedXcodeID,
                    appState: appState
                )
            } else {
                ForEach(visibleXcodes) { entry in
                    XcodeListViewRow(xcode: entry.xcode, selected: selectedXcodeID == entry.xcode.id, appState: appState)
                        .tag(entry.xcode.id)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlatformsPocket()
                .padding(.horizontal)
                .padding(.vertical, 8)
           
        }
    }
}

private struct XcodeListEntry: Identifiable {
    let index: Int
    let xcode: Xcode

    var id: Int {
        index
    }

    var listItem: XcodeListItem {
        xcode.listItem
    }
}

private struct GroupedXcodeListContent: View {
    let xcodes: [XcodeListEntry]
    @Binding var selectedXcodeID: Xcode.ID?
    let appState: AppState

    @AppStorage(PreferenceKey.expandedMajorXcodeVersions.rawValue) private var expandedMajorVersionStorage = ""
    @AppStorage(PreferenceKey.expandedMinorXcodeVersions.rawValue) private var expandedMinorVersionStorage = ""

    private var expandedMajorVersions: Set<Int> {
        get {
            Set(expandedMajorVersionStorage.split(separator: ",").compactMap { Int($0) })
        }
        nonmutating set {
            expandedMajorVersionStorage = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    private var expandedMinorVersions: Set<String> {
        get {
            Set(expandedMinorVersionStorage.split(separator: ",").map(String.init))
        }
        nonmutating set {
            expandedMinorVersionStorage = newValue.sorted().joined(separator: ",")
        }
    }

    private var majorVersionGroups: [XcodeListElementMajorVersionGroup<XcodeListEntry>] {
        xcodes.groupedByMajorVersion(item: \.listItem)
    }

    var body: some View {
        ForEach(majorVersionGroups) { majorVersionGroup in
            let isMajorExpanded = expandedMajorVersions.contains(majorVersionGroup.majorVersion)
            let majorVersions = majorVersionGroup.versions.map(\.xcode)

            XcodeVersionGroupRow(
                displayName: majorVersionGroup.displayName,
                latestRelease: majorVersions.latestRelease,
                selectedVersion: majorVersions.first { $0.selected },
                installingVersion: majorVersions.first { $0.installState.installing },
                isExpanded: isMajorExpanded,
                indentation: 0,
                appState: appState,
                onToggleExpanded: {
                    var updatedExpandedMajorVersions = expandedMajorVersions
                    var updatedExpandedMinorVersions = expandedMinorVersions

                    if isMajorExpanded {
                        updatedExpandedMajorVersions.remove(majorVersionGroup.majorVersion)
                        majorVersionGroup.minorVersionGroups.forEach {
                            updatedExpandedMinorVersions.remove($0.id)
                        }
                    } else {
                        updatedExpandedMajorVersions.insert(majorVersionGroup.majorVersion)
                    }

                    self.expandedMajorVersions = updatedExpandedMajorVersions
                    self.expandedMinorVersions = updatedExpandedMinorVersions
                }
            )
            .tag(majorVersions.first { $0.selected }?.id)

            if isMajorExpanded {
                ForEach(majorVersionGroup.minorVersionGroups) { minorVersionGroup in
                    let isMinorExpanded = expandedMinorVersions.contains(minorVersionGroup.id)
                    let minorVersions = minorVersionGroup.versions.map(\.xcode)

                    XcodeVersionGroupRow(
                        displayName: minorVersionGroup.displayName,
                        latestRelease: minorVersions.latestRelease,
                        selectedVersion: minorVersions.first { $0.selected },
                        installingVersion: minorVersions.first { $0.installState.installing },
                        isExpanded: isMinorExpanded,
                        indentation: 20,
                        appState: appState,
                        onToggleExpanded: {
                            var updatedExpandedMinorVersions = expandedMinorVersions

                            if isMinorExpanded {
                                updatedExpandedMinorVersions.remove(minorVersionGroup.id)
                            } else {
                                updatedExpandedMinorVersions.insert(minorVersionGroup.id)
                            }

                            self.expandedMinorVersions = updatedExpandedMinorVersions
                        }
                    )
                    .tag(minorVersions.first { $0.selected }?.id)

                    if isMinorExpanded {
                        ForEach(minorVersionGroup.versions) { entry in
                            XcodeListViewRow(xcode: entry.xcode, selected: selectedXcodeID == entry.xcode.id, appState: appState)
                                .padding(.leading, 40)
                                .tag(entry.xcode.id)
                        }
                    }
                }
            }
        }
    }
}

private struct XcodeVersionGroupRow: View {
    let displayName: String
    let latestRelease: Xcode?
    let selectedVersion: Xcode?
    let installingVersion: Xcode?
    let isExpanded: Bool
    let indentation: CGFloat
    let appState: AppState
    let onToggleExpanded: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)

                    icon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Xcode \(displayName)")
                            .font(.body.weight(indentation == 0 ? .medium : .regular))

                        if let latestRelease {
                            Text(verbatim: "Latest: \(latestRelease.description)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            selectControl
                .padding(.trailing, 16)
            installControl
        }
        .padding(.leading, indentation)
        .padding(.vertical, indentation == 0 ? 8 : 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let icon = latestRelease?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image(latestRelease?.version.isPrerelease == true ? "xcode-beta" : "xcode")
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(0.2)
        }
    }

    @ViewBuilder
    private var selectControl: some View {
        if selectedVersion?.selected == true {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .help("ActiveVersionDescription")
        }
    }

    @ViewBuilder
    private var installControl: some View {
        if let installingVersion,
           case let .installing(installationStep) = installingVersion.installState {
            InstallationStepRowView(
                installationStep: installationStep,
                highlighted: false,
                cancel: { appState.presentedAlert = .cancelInstall(xcode: installingVersion) }
            )
        } else if let latestRelease {
            switch latestRelease.installState {
            case .installed:
                Button("Open") { appState.open(xcode: latestRelease) }
                    .textCase(.uppercase)
                    .buttonStyle(AppStoreButtonStyle(primary: true, highlighted: false))
                    .help("OpenDescription")
            case .notInstalled:
                Button("Install") {
                    appState.checkMinVersionAndInstall(id: latestRelease.id)
                }
                .textCase(.uppercase)
                .buttonStyle(AppStoreButtonStyle(primary: false, highlighted: false))
                .help("InstallDescription")
            case .installing:
                EmptyView()
            }
        }
    }
}

private extension Array where Element == Xcode {
    var latestRelease: Xcode? {
        filter { $0.version.isNotPrerelease }
            .sorted { $0.version < $1.version }
            .last
    }
}

struct PlatformsPocket: View {
    @SwiftUI.Environment(\.openWindow) private var openWindow
   
    var body: some View {
        Button(action: {
            openWindow(id: "platforms")
        }
        ) {
            if #available(macOS 26.0, *) {
                platformsLabel
                    .glassEffect(in: .rect(cornerRadius: 8, style: .continuous))
            } else {
                platformsLabel
                .background(.quaternary.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
           
        }
        .buttonStyle(.plain)
    }
    
    var platformsLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.3.layers.3d")
                .font(.title3.weight(.medium))
            Text("PlatformsDescription")
                            Spacer()
        }
        .font(.body.weight(.medium))
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

struct XcodeListView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            XcodeListView(selectedXcodeID: .constant(nil), searchText: "", category: .all, isInstalledOnly: false, architecture: .appleSilicon)
                .environmentObject({ () -> AppState in
                    let a = AppState()
                    a.allXcodes = [
                        Xcode(version: Version("12.0.0+1234A")!, identicalBuilds: [XcodeID(version: Version("12.0.0+1234A")!), XcodeID(version: Version("12.0.0-RC+1234A")!)], installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: false, icon: nil),
                        Xcode(version: Version("12.3.0")!, installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: true, icon: nil),
                        Xcode(version: Version("12.2.0")!, installState: .notInstalled, selected: false, icon: nil),
                        Xcode(version: Version("12.1.0")!, installState: .installing(.downloading(progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40 })), selected: false, icon: nil),
                        Xcode(version: Version("12.0.0")!, installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: false, icon: nil),
                        Xcode(version: Version("10.1.0")!, installState: .notInstalled, selected: false, icon: nil),
                        Xcode(version: Version("10.0.0")!, installState: .installed(Path("/Applications/Xcode-10.0.0.app")!), selected: false, icon: nil),
                        Xcode(version: Version("9.0.0")!, installState: .notInstalled, selected: false, icon: nil),
                    ]
                    return a
                }())
        }
        .previewLayout(.sizeThatFits)
    }
}
