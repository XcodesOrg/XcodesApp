//
//  PlatformsListView.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-12-20.
//

import Foundation
import SwiftUI
import Path
import XcodesKit
import OrderedCollections

struct PlatformsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var runtimes: OrderedDictionary<DownloadableRuntime.Platform, [DownloadableRuntime]> = [:]
    @State private var selectedRuntime: DownloadableRuntime?
    
    var body: some View {
        List(selection: $selectedRuntime) {
            Text("PlatformsList.Title")
                .font(.body)
            ForEach(runtimes.elements.sorted(\.key.order), id: \.key) { platform, runtimeList in
                Section {
                    ForEach(runtimeList, id: \.self) { runtime in
                        HStack {
                            Text(runtime.name)
                            Spacer()
                            Text(runtime.downloadFileSizeString)
                            Button {
                                deleteRuntime(runtime: runtime)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .foregroundStyle(.red)
                            .buttonStyle(.plain)
                        }
                        .frame(height: 30)
                    }
                   
                } header: {
                    HStack {
                        runtimeList.first!.icon()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20)
                        Text(platform.shortName)
                            .font(.headline)
                    }
                } footer: {
                    EmptyView()
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .task {
            loadRuntimes()
        }
        .onChange(of: appState.installedRuntimes) { _ in
            loadRuntimes()
        }
    }
    
    func loadRuntimes() {
        let filteredRuntimes = appState.downloadableRuntimes.filter { runtime in
            appState.installedRuntimes.contains { $0.runtimeInfo.build == runtime.simulatorVersion.buildUpdate
            }
        }
        runtimes = OrderedDictionary(grouping: filteredRuntimes, by: { $0.platform })
    }
    
    func deleteRuntime(runtime: DownloadableRuntime) {
        appState.presentedPreferenceAlert = .deletePlatform(runtime: runtime)
    }
}


#Preview {
    PlatformsListView()
        .environmentObject({ () -> AppState in
            let a = AppState()
          
            a.installedRuntimes = installedRuntimes
            a.downloadableRuntimes = downloadableRuntimes
        
            return a
          
        }())
}
