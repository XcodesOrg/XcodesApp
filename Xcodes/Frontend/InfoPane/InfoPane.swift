import AppKit
import Path
import SwiftUI
import Version
import struct XCModel.SDKs
import struct XCModel.Compilers

struct InfoPane: View {
    @EnvironmentObject var appState: AppState
    let selectedXcodeID: Xcode.ID?
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    
    var body: some View {
        if let xcode = appState.allXcodes.first(where: { $0.id == selectedXcodeID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    icon(for: xcode)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(verbatim: "Xcode \(xcode.description) \(xcode.version.buildMetadataIdentifiersDisplay)")
                        .font(.title)
                    
                    switch xcode.installState {
                    case .notInstalled:
                        InstallButton(xcode: xcode)
                        downloadFileSize(for: xcode)
                    case .installing(let installationStep):
                        InstallationStepDetailView(installationStep: installationStep)
                            .fixedSize(horizontal: false, vertical: true)
                        CancelInstallButton(xcode: xcode)
                    case let .installed(path):
                        HStack {
                            Text(path.string)
                            Button(action: { appState.reveal(xcode: xcode) }) {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("RevealInFinder")
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
                    
                    Divider()

                    Group{
                        releaseNotes(for: xcode)
                        releaseDate(for: xcode)
                        identicalBuilds(for: xcode)
                        compatibility(for: xcode)
                        sdks(for: xcode)
                        compilers(for: xcode)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .frame(minWidth: 200, maxWidth: .infinity)
        } else {
            empty
                .frame(minWidth: 200, maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private func icon(for xcode: Xcode) -> some View {
        if case let .installed(path) = xcode.installState {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.string))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func identicalBuilds(for xcode: Xcode) -> some View {
        if !xcode.identicalBuilds.isEmpty {
            VStack(alignment: .leading) {
                HStack {
                    Text("IdenticalBuilds")
                    Image(systemName: "square.fill.on.square.fill")
                        .foregroundColor(.secondary)
                        .accessibility(hidden: true)
                        .help("IdenticalBuilds.help")
                }
                .font(.headline)
                
                ForEach(xcode.identicalBuilds, id: \.description) { version in
                    Text("• \(version.appleDescription)")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibility(label: Text("IdenticalBuilds"))
            .accessibility(value: Text(xcode.identicalBuilds.map(\.appleDescription).joined(separator: ", ")))
            .accessibility(hint: Text("IdenticalBuilds.help"))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func releaseDate(for xcode: Xcode) -> some View {
        if let releaseDate = xcode.releaseDate {
            VStack(alignment: .leading) {
                Text("ReleaseDate")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(releaseDate, style: .date)")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func releaseNotes(for xcode: Xcode) -> some View {
        if let releaseNotesURL = xcode.releaseNotesURL {
            Button(action: { openURL(releaseNotesURL) }) {
                Label("ReleaseNotes", systemImage: "link")
            }
            .buttonStyle(LinkButtonStyle())
            .contextMenu(menuItems: {
              releaseNotesMenu(for: xcode)
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("ReleaseNotes.help")
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func releaseNotesMenu(for xcode: Xcode) -> some View {
        CopyReleaseNoteButton(xcode: xcode)
    }
    
    @ViewBuilder
    private func compatibility(for xcode: Xcode) -> some View {
        if let requiredMacOSVersion = xcode.requiredMacOSVersion {
            VStack(alignment: .leading) {
                Text("Compatibility")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: localizeString("MacOSRequirement"), requiredMacOSVersion))
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
    private func downloadFileSize(for xcode: Xcode) -> some View {
        // if we've downloaded it no need to show the download size
        if let downloadFileSize = xcode.downloadFileSizeString, case .notInstalled = xcode.installState {
            VStack(alignment: .leading) {
                Text("DownloadSize")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(downloadFileSize)")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var empty: some View {
        Text("NoXcodeSelected")
            .font(.title)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
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
                            installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                            selected: true,
                            icon: NSWorkspace.shared.icon(forFile: "/Applications/Xcode-12.3.0.app"),
                            requiredMacOSVersion: "10.15.4",
                            releaseNotesURL: URL(string: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_3-release-notes/")!,
                            releaseDate: Date(),
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
                            ),
                            downloadFileSize: 242342424
                            )
                    ]
                })
                .previewDisplayName("Populated, Installed, Selected")

            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 0))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 0),
                            installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                            selected: false,
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
                            ),
                            downloadFileSize: 242342424)
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
                            ),
                            downloadFileSize: 242342424)
                    ]
                })
                .previewDisplayName("Populated, Uninstalled")

            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 1, buildMetadataIdentifiers: ["1234A"]))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 1, buildMetadataIdentifiers: ["1234A"]),
                            installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
                            selected: false,
                            icon: nil,
                            sdks: nil,
                            compilers: nil)
                    ]
                })
                .previewDisplayName("Basic, installed")

            InfoPane(selectedXcodeID: Version(major: 12, minor: 3, patch: 1, buildMetadataIdentifiers: ["1234A"]))
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [
                        .init(
                            version: Version(major: 12, minor: 3, patch: 1, buildMetadataIdentifiers: ["1234A"]),
                            installState: .installing(.downloading(progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40; $0.throughput = 232323232; $0.fileCompletedCount = 2323004; $0.fileTotalCount = 1193939393 })),
                            selected: false,
                            icon: nil,
                            sdks: nil,
                            compilers: nil)
                    ]
                })
                .previewDisplayName("Basic, installing")
            
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
