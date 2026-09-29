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
    @AppStorage(PreferenceKey.expandedMajorXcodeVersions.rawValue) private var expandedMajorVersionStorage = ""
    @AppStorage(PreferenceKey.expandedMinorXcodeVersions.rawValue) private var expandedMinorVersionStorage = ""

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

    private func latestReleaseForSelectedPrerelease(_ xcode: Xcode) -> Xcode? {
        appState.allXcodes.latestReleaseForSelectedPrerelease(xcode)
    }
    
    /// Version rows in display order, for moving the selection with the arrow keys
    private var selectableXcodeIDs: [Xcode.ID] {
        guard appState.enableGroupedXcodeList else { return visibleXcodes.map(\.xcode.id) }
        let expandedMajors = Set(expandedMajorVersionStorage.split(separator: ",").compactMap { Int($0) })
        let expandedMinors = Set(expandedMinorVersionStorage.split(separator: ",").map(String.init))
        return visibleXcodes.groupedByMajorVersion(item: \.listItem)
            .filter { expandedMajors.contains($0.majorVersion) }
            .flatMap(\.minorVersionGroups)
            .filter { expandedMinors.contains($0.id) }
            .flatMap { $0.versions.map(\.xcode.id) }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let ids = selectableXcodeIDs
        guard !ids.isEmpty else { return .ignored }
        guard let current = selectedXcodeID, let index = ids.firstIndex(of: current) else {
            selectedXcodeID = offset > 0 ? ids.first : ids.last
            return .handled
        }
        selectedXcodeID = ids[min(max(index + offset, 0), ids.count - 1)]
        return .handled
    }

    var body: some View {
        // Selection is drawn by the rows (SelectableRow) rather than List(selection:), because the sidebar's
        // system highlight can't be restyled and left tags and secondary text hard to read.
        List {
            if appState.enableGroupedXcodeList {
                GroupedXcodeListContent(
                    xcodes: visibleXcodes,
                    allXcodes: appState.allXcodes,
                    selectedXcodeID: $selectedXcodeID,
                    appState: appState
                )
            } else {
                ForEach(visibleXcodes) { entry in
                    XcodeListViewRow(
                        xcode: entry.xcode,
                        selected: selectedXcodeID == entry.xcode.id,
                        appState: appState,
                        latestReleaseForSelectedPrerelease: latestReleaseForSelectedPrerelease(entry.xcode)
                    )
                        .selectableRow(isSelected: selectedXcodeID == entry.xcode.id) { selectedXcodeID = entry.xcode.id }
                }
            }
        }
        .listStyle(.sidebar)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
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
    let allXcodes: [Xcode]
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

    private func latestReleaseForSelectedPrerelease(_ xcode: Xcode) -> Xcode? {
        allXcodes.latestReleaseForSelectedPrerelease(xcode)
    }

    /// The newest non-prerelease version across the whole list, tagged "Latest"
    private var latestStableVersion: Version? {
        allXcodes.latestRelease?.version
    }

    private func isLatestRelease(_ xcode: Xcode) -> Bool {
        guard let latestStableVersion, xcode.version.isNotPrerelease else { return false }
        return xcode.version.isEquivalent(to: latestStableVersion)
    }

    /// Latest when the group holds the newest release; otherwise, for a group of only prereleases, its newest seed.
    private func groupTag(for versions: [Xcode]) -> ReleaseTagView? {
        if versions.contains(where: isLatestRelease) {
            return .latest
        }
        guard versions.allSatisfy(\.version.isPrerelease), let newest = versions.max(by: { $0.version < $1.version }) else { return nil }
        return ReleaseTagView(prereleaseOf: newest.version)
    }

    var body: some View {
        ForEach(majorVersionGroups) { majorVersionGroup in
            let isMajorExpanded = expandedMajorVersions.contains(majorVersionGroup.majorVersion)
            let majorVersions = majorVersionGroup.versions.map(\.xcode)
            let latestMajorRelease = majorVersions.latestRelease
            let latestInstalledMajorVersion = majorVersions.latestInstalledVersion
            let majorHasActiveXcode = majorVersions.contains { $0.selected }
            let minorVersionGroups = majorVersionGroup.minorVersionGroups

            XcodeVersionGroupRow(
                displayName: "Xcode \(majorVersionGroup.displayName)",
                latestRelease: latestMajorRelease,
                latestSelectableRelease: latestMajorRelease,
                latestSelectionTarget: latestInstalledMajorVersion,
                selectedVersion: majorVersions.first { $0.selected },
                installingVersion: majorVersions.first { $0.installState.installing },
                isExpanded: isMajorExpanded,
                level: 0,
                versionCount: majorVersions.count,
                tag: majorVersions.contains(where: isLatestRelease) ? .latest : nil,
                // The active Xcode is tagged on the deepest visible row: here only while collapsed
                showsActiveTag: majorHasActiveXcode && !isMajorExpanded,
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


            if isMajorExpanded {
                ForEach(Array(minorVersionGroups.enumerated()), id: \.element.id) { minorIndex, minorVersionGroup in
                    let isMinorExpanded = expandedMinorVersions.contains(minorVersionGroup.id)
                    let minorVersions = minorVersionGroup.versions.map(\.xcode)
                    let latestInstalledMinorVersion = minorVersions.latestInstalledVersion
                    let isLastMinor = minorIndex == minorVersionGroups.count - 1
                    let minorHasActiveXcode = minorVersions.contains { $0.selected }

                    XcodeVersionGroupRow(
                        displayName: minorVersionGroup.displayName,
                        latestRelease: minorVersions.latestRelease,
                        latestSelectableRelease: latestMajorRelease,
                        latestSelectionTarget: latestInstalledMinorVersion,
                        selectedVersion: minorVersions.first { $0.selected },
                        installingVersion: minorVersions.first { $0.installState.installing },
                        isExpanded: isMinorExpanded,
                        level: 1,
                        versionCount: minorVersions.count,
                        tag: groupTag(for: minorVersions),
                        showsActiveTag: minorHasActiveXcode && !isMinorExpanded,
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
                    .treeGuides {
                        TreeGuides(guides: [
                            TreeGuide(level: 0, extent: isLastMinor ? .elbow : .tee, isHighlighted: majorHasActiveXcode && (minorHasActiveXcode || !isLastMinor))
                        ])
                    }


                    if isMinorExpanded {
                        let entries = minorVersionGroup.versions
                        ForEach(Array(entries.enumerated()), id: \.element.id) { entryIndex, entry in
                            let isLastEntry = entryIndex == entries.count - 1

                            XcodeListViewRow(
                                xcode: entry.xcode,
                                selected: selectedXcodeID == entry.xcode.id,
                                appState: appState,
                                latestReleaseForSelectedPrerelease: latestReleaseForSelectedPrerelease(entry.xcode),
                                style: .grouped,
                                isLatestRelease: isLatestRelease(entry.xcode)
                            )
                                .padding(.leading, TreeGuide.contentInset(forLevel: 2))
                                .treeGuides {
                                    TreeGuides(guides: [
                                        TreeGuide(level: 0, extent: isLastMinor ? .none : .through, isHighlighted: majorHasActiveXcode && !isLastMinor),
                                        TreeGuide(level: 1, extent: isLastEntry ? .elbow : .tee, isHighlighted: minorHasActiveXcode, branchesToLeaf: true)
                                    ])
                                }
                                .selectableRow(isSelected: selectedXcodeID == entry.xcode.id) { selectedXcodeID = entry.xcode.id }
                        }
                    }
                }
            }
        }
    }
}

/// A vertical guide line connecting a group row to its children, drawn like a file tree (├ └ │).
private struct TreeGuide: Hashable {
    enum Extent {
        /// No line; the parent's last child has already been drawn.
        case none
        /// A full-height line passing a sibling's descendants.
        case through
        /// A full-height line with a branch to this row (├).
        case tee
        /// A line ending at this row with a branch to it (└).
        case elbow
    }

    /// Chevron width plus spacing, so each level's content starts one step to the right of its parent's chevron.
    static let levelIndent: CGFloat = 22
    static let chevronWidth: CGFloat = 12

    let level: Int
    let extent: Extent
    let isHighlighted: Bool
    /// Whether this row is a leaf (no chevron), so the branch reaches further to meet its icon.
    var branchesToLeaf = false

    /// Centered under the parent's chevron.
    var x: CGFloat {
        CGFloat(level) * Self.levelIndent + Self.chevronWidth / 2
    }

    /// Where the branch drawn for this row stops, just short of the row's chevron or icon.
    var branchEnd: CGFloat {
        let childContentStart = branchesToLeaf ? Self.contentInset(forLevel: level + 1) : CGFloat(level + 1) * Self.levelIndent
        return childContentStart - 4
    }

    /// Leaf rows have no chevron, so their icon is inset to where a chevron-less row at that level would start.
    static func contentInset(forLevel level: Int) -> CGFloat {
        CGFloat(level) * levelIndent + chevronWidth + 8
    }
}

private struct TreeGuides: View {
    let guides: [TreeGuide]
    /// Where branches meet the row: the middle of its title line. Falls back to the row's middle.
    var branchY: CGFloat? = nil

    var body: some View {
        Canvas { context, size in
            let lineWidth: CGFloat = 1.5
            // Rows have a little vertical breathing room; extend past it so lines connect between rows.
            let overshoot: CGFloat = 4
            let midY = branchY ?? size.height / 2
            for guide in guides {
                let color: Color = guide.isHighlighted ? .accentColor.opacity(0.75) : .secondary.opacity(0.35)
                var path = Path()
                switch guide.extent {
                case .none:
                    continue
                case .through, .tee:
                    path.move(to: CGPoint(x: guide.x, y: -overshoot))
                    path.addLine(to: CGPoint(x: guide.x, y: size.height + overshoot))
                case .elbow:
                    path.move(to: CGPoint(x: guide.x, y: -overshoot))
                    path.addLine(to: CGPoint(x: guide.x, y: midY - 5))
                    path.addQuadCurve(to: CGPoint(x: guide.x + 5, y: midY), control: CGPoint(x: guide.x, y: midY))
                }
                if guide.extent == .tee || guide.extent == .elbow {
                    let branchStart = guide.extent == .tee ? guide.x : guide.x + 5
                    path.move(to: CGPoint(x: branchStart, y: midY))
                    path.addLine(to: CGPoint(x: guide.branchEnd, y: midY))
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct XcodeVersionGroupRow: View {
    let displayName: String
    let latestRelease: Xcode?
    let latestSelectableRelease: Xcode?
    let latestSelectionTarget: Xcode?
    let selectedVersion: Xcode?
    let installingVersion: Xcode?
    let isExpanded: Bool
    let level: Int
    let versionCount: Int
    let tag: ReleaseTagView?
    let showsActiveTag: Bool
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

                    if level == 0 {
                        icon
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: displayName)
                                .font(level == 0 ? .headline : .body.weight(.medium))
                                .treeGuideTitle()

                            if let tag {
                                tag
                            }

                            if showsActiveTag {
                                ReleaseTagView.active
                            }

                            Text(verbatim: "\(versionCount)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                                .accessibilityHidden(true)
                        }

                        if let subtitle {
                            Text(verbatim: subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Like the progress ring and Active tag, the checkmark belongs to the deepest visible row
            if !isExpanded {
                selectControl
                    .padding(.trailing, 16)
            }
            installControl
                // Same column width as the Install/Open buttons, so the progress ring lines up with them
                .frame(minWidth: 67)
        }
        .padding(.leading, CGFloat(level) * TreeGuide.levelIndent)
        .padding(.vertical, level == 0 ? 8 : 5)
        .contentShape(Rectangle())
    }

    /// "Latest: 27.0 · Active: 27.0 Beta 6"
    private var subtitle: String? {
        let parts = [
            latestRelease.map { "Latest: \($0.description)" },
            selectedVersion.map { "Active: \($0.description)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
                .opacity(0.5)
        }
    }

    @ViewBuilder
    private var selectControl: some View {
        if let selectedVersion, selectedVersion.selected, let latestSelectableRelease, latestSelectableRelease.id != selectedVersion.id {
            switch latestSelectionTarget?.installState {
            case .installed:
                if let latestSelectionTarget, latestSelectionTarget.id != selectedVersion.id {
                    Button(action: { appState.select(xcode: latestSelectionTarget) }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(staleSelectedHelpText(selectedVersion: selectedVersion, latestRelease: latestSelectableRelease, selectionTarget: latestSelectionTarget))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.yellow)
                        .help(staleSelectedHelpText(selectedVersion: selectedVersion, latestRelease: latestSelectableRelease, selectionTarget: latestSelectionTarget))
                }
            case .notInstalled:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.yellow)
                    .help(staleSelectedHelpText(selectedVersion: selectedVersion, latestRelease: latestSelectableRelease, selectionTarget: latestSelectionTarget))
            case .installing, .uninstalling, .none:
                EmptyView()
            }
        } else if selectedVersion?.selected == true {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .help("ActiveVersionDescription")
        } else if let latestSelectionTarget {
            Button(action: { appState.select(xcode: latestSelectionTarget) }) {
                // Installed but not active: green outline; the active Xcode gets the filled check
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
            .help("MakeActiveVersionDescription")
        }
    }

    private func staleSelectedHelpText(selectedVersion: Xcode, latestRelease: Xcode, selectionTarget: Xcode?) -> Text {
        switch selectionTarget?.installState {
        case .installed:
            if let selectionTarget, selectionTarget.id != selectedVersion.id {
                return Text(verbatim: "\(selectedVersion.description) selected, \(latestRelease.description) available. Click to select \(selectionTarget.description).")
            } else {
                return Text(verbatim: "\(selectedVersion.description) selected, \(latestRelease.description) available.")
            }
        case .notInstalled:
            if let selectionTarget {
                return Text(verbatim: "\(selectedVersion.description) selected, \(latestRelease.description) available. Install \(selectionTarget.description) to select it.")
            } else {
                return Text(verbatim: "\(selectedVersion.description) selected, \(latestRelease.description) available.")
            }
        case .installing, .uninstalling, .none:
            return Text(verbatim: "\(selectedVersion.description) selected, \(latestRelease.description) available.")
        }
    }

    @ViewBuilder
    private var installControl: some View {
        // Progress is shown once, on the deepest visible row: an expanded group leaves it to its children.
        if !isExpanded,
           let installingVersion,
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
            case .installing, .uninstalling:
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

    var latestInstalledVersion: Xcode? {
        filter(\.installState.installed)
            .sorted { $0.version < $1.version }
            .last
    }

    func latestReleaseForSelectedPrerelease(_ xcode: Xcode) -> Xcode? {
        guard xcode.selected, xcode.version.isPrerelease else { return nil }

        return first { candidate in
            candidate.id != xcode.id &&
                candidate.architectures == xcode.architectures &&
                candidate.version.major == xcode.version.major &&
                candidate.version.minor == xcode.version.minor &&
                candidate.version.patch == xcode.version.patch &&
                candidate.version.isNotPrerelease &&
                candidate.installState.installing == false
        }
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
        .contentShape(Rectangle())
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

// MARK: - Tree guide title anchor

/// The vertical middle of a row's title, so tree guide branches meet the title rather than the row's middle.
private struct TreeGuideTitleMidYKey: SwiftUI.PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

private let treeGuideRowSpace = "treeGuideRow"

extension View {
    /// Marks the row's title; tree guides drawn with `treeGuides(_:)` branch at its middle.
    func treeGuideTitle() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: TreeGuideTitleMidYKey.self, value: proxy.frame(in: .named(treeGuideRowSpace)).midY)
            }
        }
    }

    fileprivate func treeGuides(_ guides: @escaping () -> TreeGuides) -> some View {
        coordinateSpace(name: treeGuideRowSpace)
            .backgroundPreferenceValue(TreeGuideTitleMidYKey.self) { titleMidY in
                let base = guides()
                TreeGuides(guides: base.guides, branchY: titleMidY)
            }
    }

    /// Selects the row on click and draws a soft highlight that keeps text and tags legible.
    func selectableRow(isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
                    .padding(.horizontal, 10)
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
