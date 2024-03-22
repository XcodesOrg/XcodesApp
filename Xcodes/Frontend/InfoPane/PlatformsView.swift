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
    
    let xcode: Xcode
 
    var body: some View {
        
        let builds = xcode.sdks?.allBuilds()
        let runtimes = builds?.flatMap { sdkBuild in
            appState.downloadableRuntimes.filter {
                $0.sdkBuildUpdate?.contains(sdkBuild) ?? false
            }
        }

        ForEach(runtimes ?? [], id: \.simulatorVersion.buildUpdate) { runtime in
            runtimeView(runtime: runtime)
                .frame(minWidth: 200)
                .padding()
                .background(.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
    
    @ViewBuilder
    func runtimeView(runtime: DownloadableRuntime) -> some View {
        VStack(spacing: 10) {
            HStack {
                runtime.icon()
                Text("\(runtime.visibleIdentifier)")
                    .font(.headline)
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
