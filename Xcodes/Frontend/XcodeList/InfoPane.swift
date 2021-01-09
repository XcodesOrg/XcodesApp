import AppKit
import SwiftUI
import Version
import struct XCModel.SDKs
import struct XCModel.Compilers

struct InfoPane: View {
    @EnvironmentObject var appState: AppState
    let selectedXcodeID: Xcode.ID?
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    
    var body: some View {
        Group {
            if let xcode = appState.allXcodes.first(where: { $0.id == selectedXcodeID }) {
                VStack(spacing: 16) {
                    icon(for: xcode)
                    
                    VStack(alignment: .leading) {
                        Text("Xcode \(xcode.description)")
                            .font(.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        switch xcode.installState {
                        case .notInstalled:
                            InstallButton(xcode: xcode)
                        case .installing:
                            CancelInstallButton(xcode: xcode)
                        case .installed:
                            if let path = xcode.path {
                                HStack {
                                    Text(path)
                                    Button(action: { appState.reveal(id: xcode.id) }) {
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .help("Reveal in Finder")
                                }
                                
                                HStack {
                                    SelectButton(xcode: xcode)
                                        .disabled(xcode.selected)
                                        .help("Selected")
                                    
                                    OpenButton(xcode: xcode)
                                        .help("Open")
                                    
                                    Spacer()
                                    UninstallButton(xcode: xcode)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    releaseNotes(for: xcode)
                    compatibility(for: xcode)
                    sdks(for: xcode)
                    compilers(for: xcode)
                  
                    Spacer()
                }
            } else {
                empty
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func icon(for xcode: Xcode) -> some View {
        if let path = xcode.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func releaseNotes(for xcode: Xcode) -> some View {
        if let releaseNotesURL = xcode.releaseNotesURL {
            Button(action: { openURL(releaseNotesURL) }) {
                Label("Release Notes", systemImage: "link")
            }
            .buttonStyle(LinkButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("View Release Notes")
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func compatibility(for xcode: Xcode) -> some View {
        if let requiredMacOSVersion = xcode.requiredMacOSVersion {
            VStack(alignment: .leading) {
                Text("Compatibility")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Requires macOS \(requiredMacOSVersion) or later")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func sdks(for xcode: Xcode) -> some View {
        if let sdks = xcode.sdks {
            VStack(alignment: .leading) {
                Text("SDKs")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach([
                    ("macOS", \SDKs.macOS),
                    ("iOS", \.iOS),
                    ("watchOS", \.watchOS),
                    ("tvOS", \.tvOS),
                ], id: \.0) { row in
                    if let sdk = sdks[keyPath: row.1] {
                        Text("\(row.0): \(sdk.compactMap { $0.number }.joined(separator: ", "))")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func compilers(for xcode: Xcode) -> some View {
        if let compilers = xcode.compilers {
            VStack(alignment: .leading) {
                Text("Compilers")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach([
                    ("Swift", \Compilers.swift),
                    ("Clang", \.clang),
                    ("LLVM", \.llvm),
                    ("LLVM GCC", \.llvm_gcc),
                    ("GCC", \.gcc),
                ], id: \.0) { row in
                    if let sdk = compilers[keyPath: row.1] {
                        Text("\(row.0): \(sdk.compactMap { $0.number }.joined(separator: ", "))")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var empty: some View {
        VStack {
            Spacer()
            Text("No Xcode Selected")
                .font(.title)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct InfoPane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 0))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 0),
                            installState: .installed,
                            selected: true,
                            path: "/Applications/Xcode-12.3.0.app",
                            icon: NSWorkspace.shared.icon(forFile: "/Applications/Xcode-12.3.0.app"),
                            requiredMacOSVersion: "10.15.4",
                            releaseNotesURL: URL(string: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_3-release-notes/")!,
                            sdks: SDKs(
                                macOS: .init(number: "11.1"),
                                iOS: .init(number: "14.3"),
                                watchOS: .init(number: "7.3"),
                                tvOS: .init(number: "14.3")
                            ),
                            compilers: Compilers(
                                gcc: .init(number: "4"),
                                llvm_gcc: .init(number: "213"),
                                llvm: .init(number: "2.3"),
                                clang: .init(number: "7.3"),
                                swift: .init(number: "5.3.2")
                            ))
                    ]
                })
                .previewDisplayName("Populated, Installed, Selected")
            
            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 0))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 0),
                            installState: .installed,
                            selected: false,
                            path: "/Applications/Xcode-12.3.0.app",
                            icon: NSWorkspace.shared.icon(forFile: "/Applications/Xcode-12.3.0.app"),
                            sdks: SDKs(
                                macOS: .init(number: "11.1"),
                                iOS: .init(number: "14.3"),
                                watchOS: .init(number: "7.3"),
                                tvOS: .init(number: "14.3")
                            ),
                            compilers: Compilers(
                                gcc: .init(number: "4"),
                                llvm_gcc: .init(number: "213"),
                                llvm: .init(number: "2.3"),
                                clang: .init(number: "7.3"),
                                swift: .init(number: "5.3.2")
                            ))
                    ]
                })
                .previewDisplayName("Populated, Installed, Unselected")
            
            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 0))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 0),
                            installState: .notInstalled,
                            selected: false,
                            path: nil,
                            icon: nil,
                            sdks: SDKs(
                                macOS: .init(number: "11.1"),
                                iOS: .init(number: "14.3"),
                                watchOS: .init(number: "7.3"),
                                tvOS: .init(number: "14.3")
                            ),
                            compilers: Compilers(
                                gcc: .init(number: "4"),
                                llvm_gcc: .init(number: "213"),
                                llvm: .init(number: "2.3"),
                                clang: .init(number: "7.3"),
                                swift: .init(number: "5.3.2")
                            ))
                    ]
                })
                .previewDisplayName("Populated, Uninstalled")
            
            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 0))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 0),
                            installState: .installed,
                            selected: false,
                            path: "/Applications/Xcode-12.3.0.app",
                            icon: nil,
                            sdks: nil,
                            compilers: nil)
                    ]
                })
                .previewDisplayName("Basic, installed")
            
            InfoPane(selectedXcodeID: nil)
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                    ]
                })
                .previewDisplayName("Empty")
        }
        .frame(maxWidth: 300)
    }
}
