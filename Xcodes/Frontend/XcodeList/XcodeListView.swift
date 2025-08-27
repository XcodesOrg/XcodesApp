import Path
import SwiftUI
import Version

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
    
    var visibleXcodes: [Xcode] {
        var xcodes: [Xcode]
        switch category {
        case .all:
            xcodes = appState.allXcodes
        case .release:
            xcodes = appState.allXcodes.filter { $0.version.isNotPrerelease }
        case .beta:
            xcodes = appState.allXcodes.filter { $0.version.isPrerelease }
        case .releasePlusNewBetas:
            let releases = Set(
                appState.allXcodes
                    .filter(\.version.isNotPrerelease)
                    .map { $0.version.withoutIdentifiers() }
            )
            xcodes = appState.allXcodes.filter {
                $0.version.isNotPrerelease || !releases.contains($0.version.withoutIdentifiers())
            }
        }
        
        if architecture == .appleSilicon {
            xcodes = xcodes.filter { $0.architectures == [.arm64] }
        }
        
        
        let latestMajor = xcodes.sorted(\.version)
            .filter { $0.version.isNotPrerelease }
            .last?
            .version
            .major

        xcodes = xcodes.filter {
            if $0.installState.notInstalled,
               let latestMajor = latestMajor,
               $0.version.major < (latestMajor - min(latestMajor,allowedMajorVersions)) {
                return false
            }

            return true
        }

        if !searchText.isEmpty {
            xcodes = xcodes.filter { $0.description.contains(searchText) }
        }
        
        if isInstalledOnly {
            xcodes = xcodes.filter { $0.installState.installed }
        }
        
        return xcodes
    }
    
    var body: some View {
        List(visibleXcodes, selection: $selectedXcodeID) { xcode in
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
        }
        ) {
            HStack(spacing: 5) {
                Image(systemName: "square.3.layers.3d")
                    .font(.title3.weight(.medium))
                Text("PlatformsDescription")
								Spacer()
            }
            .font(.body.weight(.medium))
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct XcodeListView_Previews: PreviewProvider {
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
