import SwiftUI
import Version
import PromiseKit

struct XcodeListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedXcodeID: Xcode.ID?
    private let searchText: String
    private let category: XcodeListCategory
    
    init(selectedXcodeID: Binding<Xcode.ID?>, searchText: String, category: XcodeListCategory) {
        self._selectedXcodeID = selectedXcodeID
        self.searchText = searchText
        self.category = category
    }
    
    var visibleXcodes: [Xcode] {
        var xcodes: [Xcode]
        switch category {
        case .all:
            xcodes = appState.allXcodes
        case .installed:
            xcodes = appState.allXcodes.filter { $0.installed }
        }
        
        if !searchText.isEmpty {
            xcodes = xcodes.filter { $0.description.contains(searchText) }
        }
        
        return xcodes
    }
    
    var body: some View {
        List(visibleXcodes, selection: $selectedXcodeID) { xcode in
            HStack {
                appIconView(for: xcode)
                
                VStack(alignment: .leading) {    
                    Text(xcode.description)
                        .font(.body)
                    
                    Text(verbatim: xcode.path ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                selectControl(for: xcode)
                installControl(for: xcode)
            }
            .contextMenu {
                InstallButton(xcode: xcode)
                
                Divider()
                
                if xcode.installed {
                    SelectButton(xcode: xcode)
                    OpenButton(xcode: xcode)
                    RevealButton(xcode: xcode)
                    CopyPathButton(xcode: xcode)
                }
            }
        }
    }
    
    @ViewBuilder
    func appIconView(for xcode: Xcode) -> some View {
        if let icon = xcode.icon {
            Image(nsImage: icon)
        } else {
            Color.clear
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func selectControl(for xcode: Xcode) -> some View {
        if xcode.selected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .help("This version is selected as the default")
        }
    }
    
    @ViewBuilder
    private func installControl(for xcode: Xcode) -> some View {
        if xcode.selected {
            Button("DEFAULT") { appState.select(id: xcode.id) }
                .buttonStyle(AppStoreButtonStyle(installed: false, highlighted: selectedXcodeID == xcode.id))
                .disabled(true)
                .help("This version is selected as the default")
        } else if xcode.installed {
            Button("SELECT") { appState.select(id: xcode.id) }
                .buttonStyle(AppStoreButtonStyle(installed: false, highlighted: selectedXcodeID == xcode.id))
                .help("Select this version as the default")
        } else {
            Button("INSTALL") { print("Installing...") }
                .buttonStyle(AppStoreButtonStyle(installed: true, highlighted: selectedXcodeID == xcode.id))
                .help("Install this version")
        }
    }
}

struct XcodeListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            XcodeListView(selectedXcodeID: .constant(nil), searchText: "", category: .all)
                .environmentObject({ () -> AppState in
                    let a = AppState()
                    a.allXcodes = [
                        Xcode(version: Version("12.3.0")!, installState: .installed, selected: true, path: "/Applications/Xcode-12.3.0.app", icon: nil),
                        Xcode(version: Version("12.2.0")!, installState: .notInstalled, selected: false, path: nil, icon: nil),
                        Xcode(version: Version("12.1.0")!, installState: .notInstalled, selected: false, path: nil, icon: nil),
                        Xcode(version: Version("12.0.0")!, installState: .installed, selected: false, path: "/Applications/Xcode-12.3.0.app", icon: nil),
                    ]
                    return a
                }())
        }
        .previewLayout(.sizeThatFits)
    }
}
