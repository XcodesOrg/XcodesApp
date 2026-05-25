//
//  PlatformsView.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-12-18.
//

import Foundation
import SwiftUI
import XcodesKit

struct PlatformsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("selectedRuntimeArchitecture") private var selectedVariant: ArchitectureVariant = .defaultForMachine()

    let xcode: Xcode
 
    var body: some View {
        
        let builds = xcode.sdks?.allBuilds
        let runtimes = (builds?.flatMap { sdkBuild in
            appState.downloadableRuntimes.filter {
                $0.sdkBuildUpdate?.contains(sdkBuild) ?? false &&
                ($0.architectures?.isEmpty ?? true ||
                 ($0.architectures?.isUniversal ?? false && selectedVariant == .universal) ||
                 ($0.architectures?.isAppleSilicon ?? false && selectedVariant == .appleSilicon)
                )
            }
        } ?? []).removingReleaseCandidateDisplayDuplicates(installedRuntimes: appState.installedRuntimes)
        
        let architectures = Set(runtimes.flatMap { $0.architectures ?? [] })
        
        VStack {
            HStack {
                Text("Platforms")
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !architectures.isEmpty {
                    Spacer()
                    Picker("Architecture", selection: $selectedVariant) {
                        ForEach(ArchitectureVariant.allCases, id: \.self) { arch in
                            Label(variantLabel(for: arch), systemImage: arch.iconName)
                                .tag(arch)
                        }
                        .labelStyle(.trailingIcon)
                    }
                    .pickerStyle(.menu)
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .labelsHidden()
                }
            }
            
            ForEach(runtimes, id: \.identifier) { runtime in
                runtimeView(runtime: runtime)
                    .frame(minWidth: 200)
                    .padding()
                    .background(.quinary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .xcodesBackground()
        

    }

    private func variantLabel(for variant: ArchitectureVariant) -> String {
        variant == .defaultForMachine() ? "\(variant.displayString) (\(localizeString("This Mac")))" : variant.displayString
    }
    
    @ViewBuilder
    func runtimeView(runtime: DownloadableRuntime) -> some View {
        VStack(spacing: 10) {
            HStack {
                runtime.icon()
                Text("\(runtime.visibleIdentifier)")
                    .font(.headline)
                ForEach(runtime.architectures ?? [], id: \.self) { architecture in
                    TagView(text: architecture.displayString)
                }
               
                pathIfAvailable(xcode: xcode, runtime: runtime)
                
                if runtime.installState == .notInstalled {
                    // TODO: Update the downloadableRuntimes with the appropriate installState so we don't have to check path awkwardly
                    if appState.runtimeInstallPath(xcode: xcode, runtime: runtime) != nil {
                        EmptyView()
                    } else {
                        HStack {
                            Spacer()
                            DownloadRuntimeButton(runtime: runtime)
                        }
                    }
                }
					
                Spacer()
                Text(runtime.downloadFileSizeString)
                    .font(.subheadline)
						  .frame(width: 70, alignment: .trailing)
            }
			  
			  if case let .installing(installationStep) = runtime.installState {
				  HStack(alignment: .top, spacing: 5){
					  RuntimeInstallationStepDetailView(installationStep: installationStep)
						  .fixedSize(horizontal: false, vertical: true)
					  Spacer()
					  CancelRuntimeInstallButton(runtime: runtime)
				  }
			  }
        }
    }
    
    @ViewBuilder
    func pathIfAvailable(xcode: Xcode, runtime: DownloadableRuntime) -> some View {
        if let path = appState.runtimeInstallPath(xcode: xcode, runtime: runtime) {
            Button(action: { appState.reveal(path: path.string) }) {
                Image(systemName: "arrow.right.circle.fill")
            }
            .buttonStyle(PlainButtonStyle())
            .help("RevealInFinder")
        } else {
            EmptyView()
        }
    }
}

private struct RuntimeDisplayKey: Hashable {
    let platform: DownloadableRuntime.Platform
    let version: String
    let architectures: [String]

    init(_ runtime: DownloadableRuntime) {
        platform = runtime.platform
        version = runtime.completeVersion
        architectures = (runtime.architectures ?? []).map(\.rawValue).sorted()
    }
}

private extension DownloadableRuntime {
    var isReleaseCandidate: Bool {
        name.localizedCaseInsensitiveContains("Release Candidate") ||
        identifier.localizedCaseInsensitiveContains("_rc")
    }

    func shouldReplace(_ other: DownloadableRuntime, installedRuntimes: [CoreSimulatorImage]) -> Bool {
        let isInstalled = RuntimeInstallationLookupService()
            .coreSimulatorImage(for: self, in: installedRuntimes) != nil
        let otherIsInstalled = RuntimeInstallationLookupService()
            .coreSimulatorImage(for: other, in: installedRuntimes) != nil

        if isInstalled != otherIsInstalled {
            return isInstalled
        }

        if isReleaseCandidate != other.isReleaseCandidate {
            return !isReleaseCandidate
        }

        return simulatorVersion.buildUpdate.localizedStandardCompare(other.simulatorVersion.buildUpdate) == .orderedDescending
    }
}

private extension Array where Element == DownloadableRuntime {
    func removingReleaseCandidateDisplayDuplicates(installedRuntimes: [CoreSimulatorImage]) -> [DownloadableRuntime] {
        var runtimesByKey: [RuntimeDisplayKey: DownloadableRuntime] = [:]
        var keys: [RuntimeDisplayKey] = []

        for runtime in self {
            let key = RuntimeDisplayKey(runtime)

            guard let existingRuntime = runtimesByKey[key] else {
                runtimesByKey[key] = runtime
                keys.append(key)
                continue
            }

            if runtime.shouldReplace(existingRuntime, installedRuntimes: installedRuntimes) {
                runtimesByKey[key] = runtime
            }
        }

        return keys.compactMap { runtimesByKey[$0] }
    }
}

#Preview(XcodePreviewName.allCases[0].rawValue) { @MainActor in makePreviewContent(for: 0) }

@MainActor
private func makePreviewContent(for index: Int) -> some View {
    let name = XcodePreviewName.allCases[index]
    let runtimes = downloadableRuntimes

    return PlatformsView(xcode: xcodeDict[name]!)
        .environmentObject({ () -> AppState in
            let a = AppState()
            a.allXcodes = [xcodeDict[name]!]
            a.installedRuntimes = installedRuntimes
            a.downloadableRuntimes = runtimes
        
            return a
          
        }())
        .frame(width: 300)
        .padding()
}
