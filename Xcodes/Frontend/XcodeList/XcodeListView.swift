import SwiftUI
import Version
import PromiseKit

struct XcodeListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: Xcode.ID?
    @State private var searchText: String = ""
    @AppStorage("lastUpdated") private var lastUpdated: Double?
    @AppStorage("xcodeListCategory") private var category: Category = .all
    
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
    
    enum Category: String, CaseIterable, Identifiable, CustomStringConvertible {
        case all
        case installed
        
        var id: Self { self }
        
        var description: String {
            switch self {
                case .all: return "All"
                case .installed: return "Installed"
            }
        }
    }
    
    var body: some View {
        List(visibleXcodes, selection: $appState.selectedXcodeID) { xcode in
            VStack(alignment: .leading) {
                HStack {
                    Text(xcode.description)
                        .font(.body)
                    if xcode.selected {
                        Tag(text: "SELECTED")
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Button(xcode.installed ? "INSTALLED" : "INSTALL") {
                        print("Installing...")
                    }
                    .buttonStyle(AppStoreButtonStyle(installed: xcode.installed,
                                                     highlighted: appState.selectedXcodeID == xcode.id))
                    .disabled(xcode.installed)
                }
                Text(verbatim: xcode.path ?? "")
                    .font(.caption)
                    .foregroundColor(appState.selectedXcodeID == xcode.id ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.secondaryLabelColor))
            }
            .contextMenu {
                InstallButton(xcode: xcode)

                Divider()

                if xcode.installed {
                    SelectButton(xcode: xcode)
                    LaunchButton(xcode: xcode)
                    RevealButton(xcode: xcode)
                    CopyPathButton(xcode: xcode)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: appState.update) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut(KeyEquivalent("r"))
                .disabled(appState.isUpdating)
                .isHidden(appState.isUpdating)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.5, anchor: .center)
                        .isHidden(!appState.isUpdating)
                )
            }
            ToolbarItem(placement: .principal) {
                Picker("", selection: $category) {
                    ForEach(Category.allCases, id: \.self) {
                        Text($0.description).tag($0)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            ToolbarItem {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
        }
        .navigationSubtitle(subtitleText)
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .alert(item: $appState.error) { error in
            Alert(title: Text(error.title), 
                  message: Text(verbatim: error.message), 
                  dismissButton: .default(Text("OK")))
        }
        /*
         Removing this for now, because it's overriding the error alert that's being worked on above.
         .alert(item: $appState.xcodeBeingConfirmedForUninstallation) { xcode in
             Alert(title: Text("Uninstall Xcode \(xcode.description)?"), 
                   message: Text("It will be moved to the Trash, but won't be emptied."), 
                   primaryButton: .destructive(Text("Uninstall"), action: { self.appState.uninstall(id: xcode.id) }), 
                   secondaryButton: .cancel(Text("Cancel")))
         }
         **/
        .sheet(isPresented: $appState.secondFactorData.isNotNil) {
            secondFactorView(appState.secondFactorData!)
                .environmentObject(appState)
        }
    }
    
    @ViewBuilder
    func secondFactorView(_ secondFactorData: AppState.SecondFactorData) -> some View {
        switch secondFactorData.option {
        case .codeSent:
            SignIn2FAView(isPresented: $appState.secondFactorData.isNotNil, authOptions: secondFactorData.authOptions, sessionData: secondFactorData.sessionData)
        case .smsSent(let trustedPhoneNumber):
            SignInSMSView(isPresented: $appState.secondFactorData.isNotNil, trustedPhoneNumber: trustedPhoneNumber, authOptions: secondFactorData.authOptions, sessionData: secondFactorData.sessionData)
        case .smsPendingChoice:
            SignInPhoneListView(isPresented: $appState.secondFactorData.isNotNil, authOptions: secondFactorData.authOptions, sessionData: secondFactorData.sessionData)
        }
    }
    
    private var subtitleText: Text {
        if let lastUpdated = lastUpdated.map(Date.init(timeIntervalSince1970:)) {
            return Text("Updated at \(lastUpdated, style: .date) \(lastUpdated, style: .time)")
        } else {
            return Text("")
        }
    }
}

struct XcodeListView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            XcodeListView()
                .environmentObject({ () -> AppState in
                    let a = AppState()
                    a.allXcodes = [
                        Xcode(version: Version("12.3.0")!, installState: .installed, selected: true, path: nil),
                        Xcode(version: Version("12.2.0")!, installState: .notInstalled, selected: false, path: nil),
                        Xcode(version: Version("12.1.0")!, installState: .notInstalled, selected: false, path: nil),
                        Xcode(version: Version("12.0.0")!, installState: .installed, selected: false, path: nil),
                    ]
                    return a
                }())
        }
        .previewLayout(.sizeThatFits)
    }
}

extension Optional {
    /// Note that this is lossy when setting, so you can really only set it to nil, but this is sufficient for mapping `Binding<Item?>` to `Binding<Bool>` for Alerts, Popovers, etc.
    var isNotNil: Bool {
        get { self != nil }
        set { self = newValue ? self : nil }
    }
}
