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
    @State private var expansion = XcodeListExpansion()
    @State private var visibleXcodes: [XcodeListEntry] = []
    @State private var groupedSnapshot = XcodeGroupedListSnapshot(xcodes: [], allXcodes: [])

    init(selectedXcodeID: Binding<Xcode.ID?>, searchText: String, category: XcodeListCategory, isInstalledOnly: Bool, architecture: XcodeListArchitecture) {
        self._selectedXcodeID = selectedXcodeID
        self.searchText = searchText
        self.category = category
        self.isInstalledOnly = isInstalledOnly
        self.architecture = architecture
    }
    
    private func updateListSnapshot(xcodes: [Xcode]? = nil) {
        let allXcodes = xcodes ?? appState.allXcodes
        let entries = allXcodes
            .enumerated()
            .map { XcodeListEntry(index: $0.offset, xcode: $0.element) }
            .applying(XcodeListFilters(
                versionFilter: category.versionFilter,
                architectureFilters: architecture.architectureFilters,
                allowedMajorVersions: allowedMajorVersions,
                searchText: searchText,
                installedOnly: isInstalledOnly
            ), item: \.listItem)
        let snapshot = XcodeGroupedListSnapshot(xcodes: entries, allXcodes: allXcodes)
        withAnimation(visibleXcodes.isEmpty ? nil : .easeInOut(duration: 0.18)) {
            visibleXcodes = entries
            groupedSnapshot = snapshot
        }
    }

    private func latestReleaseForSelectedPrerelease(_ xcode: Xcode) -> Xcode? {
        appState.allXcodes.latestReleaseForSelectedPrerelease(xcode)
    }
    
    /// Version rows in display order, for moving the selection with the arrow keys
    private var selectableXcodeIDs: [Xcode.ID] {
        guard appState.enableGroupedXcodeList else { return visibleXcodes.map(\.xcode.id) }
        return groupedSnapshot.rows(expansion: expansion).compactMap { row in
            if case let .version(entry, _, _, _) = row { return entry.xcode.id }
            return nil
        }
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
                    snapshot: groupedSnapshot,
                    expansion: $expansion,
                    selectedXcodeID: $selectedXcodeID,
                    appState: appState
                )
            } else {
                ForEach(visibleXcodes) { entry in
                    XcodeListViewRow(
                        xcode: entry.xcode,
                        selected: selectedXcodeID == entry.xcode.id,
                        appState: appState,
                        latestReleaseForSelectedPrerelease: latestReleaseForSelectedPrerelease(entry.xcode),
                        isLatestRelease: entry.xcode.version.isNotPrerelease && groupedSnapshot.latestStableVersion.map { entry.xcode.version.isEquivalent(to: $0) } == true
                    )
                        .selectableRow(isSelected: selectedXcodeID == entry.xcode.id) { selectedXcodeID = entry.xcode.id }
                }
            }
        }
        .onReceive(appState.$allXcodes) { updateListSnapshot(xcodes: $0) }
        .onChange(of: searchText) { updateListSnapshot() }
        .onChange(of: category) { updateListSnapshot() }
        .onChange(of: architecture) { updateListSnapshot() }
        .onChange(of: isInstalledOnly) { updateListSnapshot() }
        .onChange(of: allowedMajorVersions) { updateListSnapshot() }
        .task(id: expansion) {
            // Persist after the UI has expanded, coalescing rapid clicks.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            expansion.save()
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

struct XcodeListEntry: Identifiable {
    let index: Int
    let xcode: Xcode

    var id: Int {
        index
    }

    var listItem: XcodeListItem {
        xcode.listItem
    }
}

/// Expansion is local UI state; saving it never delays a disclosure click.
struct XcodeListExpansion: Equatable, Hashable {
    var majorVersions: Set<Int>
    var minorVersions: Set<String>

    init(majorVersions: Set<Int>, minorVersions: Set<String>) {
        self.majorVersions = majorVersions
        self.minorVersions = minorVersions
    }

    init() {
        let defaults = UserDefaults.standard
        majorVersions = Set((defaults.string(forKey: PreferenceKey.expandedMajorXcodeVersions.rawValue) ?? "").split(separator: ",").compactMap { Int($0) })
        minorVersions = Set((defaults.string(forKey: PreferenceKey.expandedMinorXcodeVersions.rawValue) ?? "").split(separator: ",").map(String.init))
    }

    mutating func toggleMajor(_ major: Int, minorIDs: [String]) {
        if majorVersions.remove(major) != nil {
            minorVersions.subtract(minorIDs)
        } else {
            majorVersions.insert(major)
        }
    }

    mutating func toggleMinor(_ id: String) {
        if minorVersions.remove(id) == nil { minorVersions.insert(id) }
    }

    func save() {
        UserDefaults.standard.set(majorVersions.sorted().map(String.init).joined(separator: ","), forKey: PreferenceKey.expandedMajorXcodeVersions.rawValue)
        UserDefaults.standard.set(minorVersions.sorted().joined(separator: ","), forKey: PreferenceKey.expandedMinorXcodeVersions.rawValue)
    }
}

/// Build summaries only when the dataset or filters change, not when a group opens.
struct XcodeGroupedListSnapshot {
    struct Summary {
        let displayName: String
        let latestRelease: Xcode?
        let latestSelectableRelease: Xcode?
        let latestSelectionTarget: Xcode?
        let selectedVersion: Xcode?
        let installingVersion: Xcode?
        let versionCount: Int
        let tag: ReleaseTagView?

        init(versions: [Xcode], displayName: String, latestSelectableRelease: Xcode?, latestStableVersion: Version?, isMajor: Bool) {
            self.displayName = displayName
            latestRelease = versions.latestRelease
            self.latestSelectableRelease = latestSelectableRelease
            latestSelectionTarget = versions.latestInstalledVersion
            selectedVersion = versions.first { $0.selected }
            installingVersion = versions.first { $0.installState.installing }
            versionCount = versions.count
            if let latestStableVersion, versions.contains(where: { $0.version.isNotPrerelease && $0.version.isEquivalent(to: latestStableVersion) }) {
                tag = .latest
            } else if !isMajor, versions.allSatisfy(\.version.isPrerelease), let newest = versions.max(by: { $0.version < $1.version }) {
                tag = ReleaseTagView(prereleaseOf: newest.version)
            } else {
                tag = nil
            }
        }
    }

    struct Minor {
        let id: String
        let summary: Summary
        let entries: [XcodeListEntry]
    }

    struct Major {
        let id: Int
        let summary: Summary
        let minors: [Minor]
    }

    enum Row: Identifiable {
        case major(Major, expanded: Bool)
        case minor(Minor, expanded: Bool, isLast: Bool)
        case version(XcodeListEntry, isLastMinor: Bool, isLastEntry: Bool, latestRelease: Xcode?)

        var id: String {
            switch self {
            case let .major(group, _): return "major-\(group.id)"
            case let .minor(group, _, _): return "minor-\(group.id)"
            case let .version(entry, _, _, _): return "version-\(entry.xcode.id)"
            }
        }
    }

    let majors: [Major]
    let latestStableVersion: Version?
    private let replacements: [Xcode.ID: Xcode]

    init(xcodes: [XcodeListEntry], allXcodes: [Xcode]) {
        let latestStable = allXcodes.latestRelease?.version
        latestStableVersion = latestStable
        replacements = Dictionary(allXcodes.compactMap { xcode in
            allXcodes.latestReleaseForSelectedPrerelease(xcode).map { (xcode.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        majors = xcodes.groupedByMajorVersion(item: \.listItem).map { major in
            let versions = major.versions.map(\.xcode)
            let latest = versions.latestRelease
            return Major(
                id: major.majorVersion,
                summary: Summary(versions: versions, displayName: "Xcode \(major.displayName)", latestSelectableRelease: latest, latestStableVersion: latestStable, isMajor: true),
                minors: major.minorVersionGroups.map { minor in
                    Minor(id: minor.id,
                          summary: Summary(versions: minor.versions.map(\.xcode), displayName: minor.displayName, latestSelectableRelease: latest, latestStableVersion: latestStable, isMajor: false),
                          entries: minor.versions)
                }
            )
        }
    }

    func rows(expansion: XcodeListExpansion) -> [Row] {
        var rows: [Row] = []
        for major in majors {
            let expanded = expansion.majorVersions.contains(major.id)
            rows.append(.major(major, expanded: expanded))
            guard expanded else { continue }
            for (minorIndex, minor) in major.minors.enumerated() {
                let minorExpanded = expansion.minorVersions.contains(minor.id)
                let isLastMinor = minorIndex == major.minors.count - 1
                rows.append(.minor(minor, expanded: minorExpanded, isLast: isLastMinor))
                guard minorExpanded else { continue }
                for (entryIndex, entry) in minor.entries.enumerated() {
                    rows.append(.version(entry, isLastMinor: isLastMinor, isLastEntry: entryIndex == minor.entries.count - 1, latestRelease: replacements[entry.xcode.id]))
                }
            }
        }
        return rows
    }
}

private struct GroupedXcodeListContent: View {
    let snapshot: XcodeGroupedListSnapshot
    @Binding var expansion: XcodeListExpansion
    @Binding var selectedXcodeID: Xcode.ID?
    let appState: AppState

    var body: some View {
        // One flat collection lets List identify rows without walking nested, variable-size ForEach views.
        ForEach(snapshot.rows(expansion: expansion)) { row in
            switch row {
            case let .major(group, expanded):
                groupRow(group.summary, expanded: expanded, level: 0) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expansion.toggleMajor(group.id, minorIDs: group.minors.map(\.id))
                    }
                }
            case let .minor(group, expanded, isLast):
                groupRow(group.summary, expanded: expanded, level: 1) {
                    withAnimation(.easeInOut(duration: 0.18)) { expansion.toggleMinor(group.id) }
                }
                .treeGuides { TreeGuides(guides: [TreeGuide(level: 0, extent: isLast ? .elbow : .tee)]) }
            case let .version(entry, isLastMinor, isLastEntry, latestRelease):
                XcodeListViewRow(
                    xcode: entry.xcode,
                    selected: selectedXcodeID == entry.xcode.id,
                    appState: appState,
                    latestReleaseForSelectedPrerelease: latestRelease,
                    style: .grouped,
                    isLatestRelease: entry.xcode.version.isNotPrerelease && snapshot.latestStableVersion.map { entry.xcode.version.isEquivalent(to: $0) } == true
                )
                .padding(.leading, TreeGuide.contentInset(forLevel: 2))
                .treeGuides {
                    TreeGuides(guides: [
                        TreeGuide(level: 0, extent: isLastMinor ? .none : .through),
                        TreeGuide(level: 1, extent: isLastEntry ? .elbow : .tee, branchesToLeaf: true)
                    ])
                }
                .selectableRow(isSelected: selectedXcodeID == entry.xcode.id) { selectedXcodeID = entry.xcode.id }
            }
        }
    }

    private func groupRow(_ summary: XcodeGroupedListSnapshot.Summary, expanded: Bool, level: Int, toggle: @escaping () -> Void) -> some View {
        XcodeVersionGroupRow(
            displayName: summary.displayName,
            latestRelease: summary.latestRelease,
            latestSelectableRelease: summary.latestSelectableRelease,
            latestSelectionTarget: summary.latestSelectionTarget,
            selectedVersion: summary.selectedVersion,
            installingVersion: summary.installingVersion,
            isExpanded: expanded,
            level: level,
            versionCount: summary.versionCount,
            tag: summary.tag,
            showsActiveTag: summary.selectedVersion != nil && !expanded,
            appState: appState,
            onToggleExpanded: toggle
        )
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
                let color = Color.secondary.opacity(0.35)
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
    @ObservedObject var appState: AppState
    let onToggleExpanded: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleExpanded) {
                // Nested rows line the chevron up with the title, where the tree guide branch ends;
                // top-level rows center it on the icon.
                HStack(alignment: level == 0 ? .center : .firstTextBaseline, spacing: 8) {
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
                                .fixedSize(horizontal: true, vertical: false)
                                .treeGuideTitle()

                            if appState.showTags, let tag {
                                tag
                            }

                            if appState.showTags && showsActiveTag {
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

            // Like the progress ring and Active tag, the checkmark and Open/Install belong to the deepest
            // visible row, so an expanded group leaves them to the rows below it
            if !isExpanded {
                selectControl
                    .padding(.trailing, 16)
                installControl
                    // Same column width as the Install/Open buttons, so the progress ring lines up with them
                    .frame(minWidth: 67)
            }
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
