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
                        .foregroundColor(selectedXcodeID == xcode.id ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.secondaryLabelColor))
                }
                
                
                Spacer()
                
                if xcode.selected {
                    Tag(text: "SELECTED")
                        .foregroundColor(.green)
                }
                
                Button(xcode.installed ? "INSTALLED" : "INSTALL") {
                    print("Installing...")
                }
                .buttonStyle(AppStoreButtonStyle(installed: xcode.installed,
                                                 highlighted: selectedXcodeID == xcode.id))
                .disabled(xcode.installed)
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
