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
    @AppStorage("selectedRuntimeArchitecture") private var selectedRuntimeArchitecture: Architecture = .arm64

    let xcode: Xcode
 
    var body: some View {
        
        let builds = xcode.sdks?.allBuilds()
        let runtimes = builds?.flatMap { sdkBuild in
            appState.downloadableRuntimes.filter {
                $0.sdkBuildUpdate?.contains(sdkBuild) ?? false &&
                ($0.architectures?.isEmpty ?? true ||
                $0.architectures?.contains(selectedRuntimeArchitecture) ?? false)
            }
        }
        
        let architectures = Set((runtimes ?? []).flatMap { $0.architectures ?? [] })
        
        VStack {
            HStack {
                Text("Platforms")
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !architectures.isEmpty {
                    Spacer()
                    Picker("Architecture", selection: $selectedRuntimeArchitecture) {
                        ForEach(Architecture.allCases, id: \.self) { arch in
                            Label(arch.displayString, systemImage: arch.iconName)
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
            
            ForEach(runtimes ?? [], id: \.identifier) { runtime in
                runtimeView(runtime: runtime)
                    .frame(minWidth: 200)
                    .padding()
                    .background(.quinary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .xcodesBackground()
        

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

#Preview(XcodePreviewName.allCases[0].rawValue) { makePreviewContent(for: 0) }

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
