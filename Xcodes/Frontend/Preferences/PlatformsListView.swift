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
        runtimes = Self.installedRuntimeRows(
            downloadableRuntimes: appState.downloadableRuntimes,
            installedRuntimes: appState.installedRuntimes
        )
    }

    /// Builds the grouped list of installed simulator runtimes for display.
    ///
    /// Apple's downloadable runtime index can list several records for the same
    /// installed build (e.g. a Universal and an Apple Silicon-only download share
    /// the same `simulatorVersion.buildUpdate` but differ in `identifier` and
    /// `architectures`). A single installed runtime must therefore collapse to a
    /// single row, otherwise the same platform appears multiple times.
    nonisolated static func installedRuntimeRows(
        downloadableRuntimes: [DownloadableRuntime],
        installedRuntimes: [CoreSimulatorImage]
    ) -> OrderedDictionary<DownloadableRuntime.Platform, [DownloadableRuntime]> {
        var rows: [DownloadableRuntime] = []
        var seenBuilds = Set<String>()

        for installed in installedRuntimes {
            let build = installed.runtimeInfo.build
            guard !seenBuilds.contains(build) else { continue }

            let candidates = downloadableRuntimes.filter { $0.simulatorVersion.buildUpdate == build }
            guard let row = bestMatch(for: installed, among: candidates) else { continue }

            seenBuilds.insert(build)
            rows.append(row)
        }

        return OrderedDictionary(grouping: rows, by: { $0.platform })
    }

    /// Picks the downloadable record that best represents an installed runtime,
    /// preferring the variant whose architectures match what is installed.
    private nonisolated static func bestMatch(
        for installed: CoreSimulatorImage,
        among candidates: [DownloadableRuntime]
    ) -> DownloadableRuntime? {
        guard !candidates.isEmpty else { return nil }

        if let installedArchitectures = installed.runtimeInfo.supportedArchitectures,
           let exactMatch = candidates.first(where: { ($0.architectures ?? []) == installedArchitectures }) {
            return exactMatch
        }

        return candidates.first
    }
    
    func deleteRuntime(runtime: DownloadableRuntime) {
        appState.presentedPreferenceAlert = .deletePlatform(runtime: runtime)
    }
}


#Preview { @MainActor in
    PlatformsListView()
        .environmentObject({ () -> AppState in
            let a = AppState()
          
            a.installedRuntimes = installedRuntimes
            a.downloadableRuntimes = downloadableRuntimes
        
            return a
          
        }())
}
