//
//  RuntimesView.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-11-23.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct RuntimesView: View {
    @EnvironmentObject var appState: AppState
    let xcode: Xcode
    
    var body: some View {
        VStack(alignment: .leading) {
                    Text("Platforms")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    let builds = xcode.sdks?.allBuilds()
                    let runtimes = builds?.flatMap { sdkBuild in
                        appState.downloadableRuntimes.filter {
                            $0.sdkBuildUpdate == sdkBuild
                        }
                    }
                    
                    ForEach(runtimes ?? [], id: \.simulatorVersion.buildUpdate) { runtime in
                        VStack {
                            HStack {
                                Text("\(runtime.visibleIdentifier)")
                                    .font(.subheadline)
                                Spacer()
                                Text(runtime.downloadFileSizeString)
                                    .font(.subheadline)
                                
                                // it's installed if we have a path
                                if let path = appState.runtimeInstallPath(xcode: xcode, runtime: runtime) {
                                    Button(action: { appState.reveal(path: path.string) }) {
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .help("RevealInFinder")
                                } else {
                                    DownloadRuntimeButton(runtime: runtime)
                                }
                            }
                            switch runtime.installState {
                                
                            case .installing(let installationStep):
                                RuntimeInstallationStepDetailView(installationStep: installationStep)
                                    .fixedSize(horizontal: false, vertical: true)
                            default:
                                EmptyView()
                            }
                        }
                       
                    }
                }
    }
}

//#Preview {
//    RuntimesView()
//}
