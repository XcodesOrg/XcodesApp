import AppKit
import XcodesKit
import Path
import SwiftUI
import Version
import struct XCModel.Compilers
import struct XCModel.SDKs

struct InfoPane: View {
    let xcode: Xcode
    var body: some View {
        if #available(macOS 14.0, *) {
            mainContent
                .contentMargins(10, for: .scrollContent)
        } else {
            mainContent
                .padding()
        }
    }
    
    private var mainContent: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top) {
                VStack {
                    VStack(spacing: 5) {
                        HStack {
                            IconView(xcode: xcode)
                            
                            Text(verbatim: "Xcode \(xcode.description) \(xcode.version.buildMetadataIdentifiersDisplay)")
                                .font(.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        InfoPaneControls(xcode: xcode)
                    }
                    .xcodesBackground()
                    
                    VStack {
                        Text("Platforms")
                            .font(.title3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PlatformsView(xcode: xcode)
                    }
                    .xcodesBackground()
                }
                .frame(minWidth: 380)
                
                VStack(alignment: .leading) {
                    ReleaseDateView(date: xcode.releaseDate, url: xcode.releaseNotesURL)
                    CompatibilityView(requiredMacOSVersion: xcode.requiredMacOSVersion)
                    IdenticalBuildsView(builds: xcode.identicalBuilds)
                    SDKandCompilers
                }
                .frame(width: 200)
                
            }
        }
    }
    
    @ViewBuilder
    var SDKandCompilers: some View {
        VStack(alignment: .leading, spacing: 16) {
            SDKsView(sdks: xcode.sdks)
            CompilersView(compilers: xcode.compilers)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

#Preview(XcodePreviewName.allCases[0].rawValue) { makePreviewContent(for: 0) }
#Preview(XcodePreviewName.allCases[1].rawValue) { makePreviewContent(for: 1) }
#Preview(XcodePreviewName.allCases[2].rawValue) { makePreviewContent(for: 2) }
#Preview(XcodePreviewName.allCases[3].rawValue) { makePreviewContent(for: 3) }
#Preview(XcodePreviewName.allCases[4].rawValue) { makePreviewContent(for: 4) }

private func makePreviewContent(for index: Int) -> some View {
    let name = XcodePreviewName.allCases[index]
    return InfoPane(xcode: xcodeDict[name]!)
        .environmentObject(configure(AppState()) {
            $0.allXcodes = [xcodeDict[name]!]
        })
        .frame(width: 300, height: 400)
        .padding()
}

enum XcodePreviewName: String, CaseIterable, Identifiable {
    case Populated_Installed_Selected
    case Populated_Installed_Unselected
    case Populated_Uninstalled
    case Basic_Installed
    case Basic_Installing
    
    var id: XcodePreviewName { self }
}

var xcodeDict: [XcodePreviewName: Xcode] = [
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
        installState: .installing(.downloading(
            progress: configure(Progress()) {
                $0.kind = .file
                $0.fileOperationKind = .downloading
                $0.estimatedTimeRemaining = 123
                $0.totalUnitCount = 11_944_848_484
                $0.completedUnitCount = 848_444_920
                $0.throughput = 9_211_681
            }
        )),
        selected: false,
        icon: nil,
        sdks: nil,
        compilers: nil
    ),
]

var downloadableRuntimes: [DownloadableRuntime] = {
    var runtimes = try! JSONDecoder().decode([DownloadableRuntime].self, from: Current.files.contents(atPath: Path.runtimeCacheFile.string)!)
    // set iOS to installed
    let iOSIndex = 0//runtimes.firstIndex { $0.sdkBuildUpdate.contains == "19E239" }!
    var iOSRuntime = runtimes[iOSIndex]
    iOSRuntime.installState = .installed
    runtimes[iOSIndex] = iOSRuntime
    
    let watchOSIndex = 0//runtimes.firstIndex { $0.sdkBuildUpdate.first == "20R362" }!
    var runtime = runtimes[watchOSIndex]
    runtime.installState = .installing(
        RuntimeInstallationStep.downloading(
            progress:configure(Progress()) {
                $0.kind = .file
                $0.fileOperationKind = .downloading
                $0.estimatedTimeRemaining = 123
                $0.totalUnitCount = 11_944_848_484
                $0.completedUnitCount = 848_444_920
                $0.throughput = 9_211_681
            }
        )
    )
    runtimes[watchOSIndex] = runtime
    
    return runtimes
}()

var installedRuntimes: [CoreSimulatorImage] = {
    [CoreSimulatorImage(uuid: "85B22F5B-048B-4331-B6E2-F4196D8B7475", path: ["relative" : "file:///Library/Developer/CoreSimulator/Images/85B22F5B-048B-4331-B6E2-F4196D8B7475.dmg"], runtimeInfo: CoreSimulatorRuntimeInfo(build: "19E240")),
     CoreSimulatorImage(uuid: "85B22F5B-048B-4331-B6E2-F4196D8B7473", path: ["relative" : "file:///Library/Developer/CoreSimulator/Images/85B22F5B-048B-4331-B6E2-F4196D8B7475.dmg"], runtimeInfo: CoreSimulatorRuntimeInfo(build: "21N5233f"))]
}()


private let _versionNoMeta = Version(major: 12, minor: 3, patch: 0)
private let _versionWithMeta = Version(major: 12, minor: 3, patch: 1, buildMetadataIdentifiers: ["1234A"])
private let _path = "/Applications/Xcode-12.3.0.app"
private let _requiredMacOSVersion = "10.15.4"
private let _sdks = SDKs(
    macOS: .init(number: "11.1"),
    iOS: .init(number: "15.4", "19E239"),
    watchOS: .init(number: "7.3", "20R362"),
    tvOS: .init(number: "14.3", "20K67"),
    visionOS: .init(number: "1.0", "21N5233e")
)
private let _compilers = Compilers(
    gcc: .init(number: "4"),
    llvm_gcc: .init(number: "213"),
    llvm: .init(number: "2.3"),
    clang: .init(number: "7.3"),
    swift: .init(number: "5.3.2")
)
private let _downloadFileSize: Int64 = 242_342_424
