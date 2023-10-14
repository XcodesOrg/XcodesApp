import AppKit
import Path
import SwiftUI
import Version
import struct XCModel.Compilers
import struct XCModel.SDKs

struct InfoPane: View {
    let xcode: Xcode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IconView(installState: xcode.installState)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(verbatim: "Xcode \(xcode.description) \(xcode.version.buildMetadataIdentifiersDisplay)")
                    .font(.title)

                switch xcode.installState {
                case .notInstalled:
                    NotInstalledStateButtons(
                        downloadFileSizeString: xcode.downloadFileSizeString,
                        id: xcode.id
                    )
                case let .installing(installationStep):
                    InstallationStepDetailView(installationStep: installationStep)
                    CancelInstallButton(xcode: xcode)
                case .installed:
                    InstalledStateButtons(xcode: xcode)
                }

                Divider()

                Group {
                    ReleaseNotesView(url: xcode.releaseNotesURL)
                    ReleaseDateView(date: xcode.releaseDate)
                    IdenticalBuildsView(builds: xcode.identicalBuilds)
                    CompatibilityView(requiredMacOSVersion: xcode.requiredMacOSVersion)
                    SDKsView(sdks: xcode.sdks)
                    CompilersView(compilers: xcode.compilers)
                }

                Spacer()
            }
        }
    }
}

struct InfoPane_Previews: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var name: PreviewName = .Populated_Installed_Selected

    var body: some View {
        VStack {
            InfoPane(xcode: xcode)
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [xcode]
                })
                .border(.red)
                .frame(width: 300, height: 400)
            Spacer()
            Picker("Preview Name", selection: $name) {
                ForEach(PreviewName.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.inline)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    var xcode: Xcode { xcodeDict[name]! }
}

private enum PreviewName: String, CaseIterable, Identifiable {
    case Populated_Installed_Selected
    case Populated_Installed_Unselected
    case Populated_Uninstalled
    case Basic_Installed
    case Basic_Installing

    var id: PreviewName { self }
}

private var xcodeDict: [PreviewName: Xcode] = [
    .Populated_Installed_Selected: .init(
        version: _versionNoMeta,
        installState: .installed(Path(_path)!),
        selected: true,
        icon: NSWorkspace.shared.icon(forFile: _path),
        requiredMacOSVersion: _requiredMacOSVersion,
        releaseNotesURL: URL(string: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_3-release-notes/")!,
        releaseDate: Date(),
        sdks: _sdks,
        compilers: _compilers,
        downloadFileSize: _downloadFileSize
    ),
    .Populated_Installed_Unselected: .init(
        version: _versionNoMeta,
        installState: .installed(Path(_path)!),
        selected: false,
        icon: NSWorkspace.shared.icon(forFile: _path),
        sdks: _sdks,
        compilers: _compilers,
        downloadFileSize: _downloadFileSize
    ),
    .Populated_Uninstalled: .init(
        version: Version(major: 12, minor: 3, patch: 0),
        installState: .notInstalled,
        selected: false,
        icon: nil,
        sdks: _sdks,
        compilers: _compilers,
        downloadFileSize: _downloadFileSize
    ),
    .Basic_Installed: .init(
        version: _versionWithMeta,
        installState: .installed(Path(_path)!),
        selected: false,
        icon: nil,
        sdks: nil,
        compilers: nil
    ),
    .Basic_Installing: .init(
        version: _versionWithMeta,
        installState: .installing(.downloading(progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40; $0.throughput = 232_323_232; $0.fileCompletedCount = 2_323_004; $0.fileTotalCount = 1_193_939_393 })),
        selected: false,
        icon: nil,
        sdks: nil,
        compilers: nil
    ),
]

private let _versionNoMeta = Version(major: 12, minor: 3, patch: 0)
private let _versionWithMeta = Version(major: 12, minor: 3, patch: 1, buildMetadataIdentifiers: ["1234A"])
private let _path = "/Applications/Xcode-12.3.0.app"
private let _requiredMacOSVersion = "10.15.4"
private let _sdks = SDKs(
    macOS: .init(number: "11.1"),
    iOS: .init(number: "14.3"),
    watchOS: .init(number: "7.3"),
    tvOS: .init(number: "14.3")
)
private let _compilers = Compilers(
    gcc: .init(number: "4"),
    llvm_gcc: .init(number: "213"),
    llvm: .init(number: "2.3"),
    clang: .init(number: "7.3"),
    swift: .init(number: "5.3.2")
)
private let _downloadFileSize: Int64 = 242_342_424
