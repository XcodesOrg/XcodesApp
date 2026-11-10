//
//  BottomStatusBar.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2022-06-03.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

struct BottomStatusModifier: ViewModifier {
    var cleanupModel: CleanupModel? = nil
    @EnvironmentObject var appState: AppState
    @AppStorage(PreferenceKey.hideSupportXcodes.rawValue) var hideSupportXcodes = false

    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            VStack(spacing: 0) {
                Divider()
                HStack {
                    if let cleanupModel {
                        CleanupStatusLink(model: cleanupModel)
                    }
                    Text(appState.bottomStatusBarMessage)
                            .font(.subheadline)
                    Spacer()
                    if !hideSupportXcodes {
                        Button(action: {
                            openURL(URL(string: "https://opencollective.com/xcodesapp")!)
                        }) {
                            HStack {
                                Image(systemName: "heart.circle")
                                Text("Support.Xcodes")
                            }
                        }
                    }
                    Text(verbatim: "\(Bundle.main.shortVersion!) (\(Bundle.main.version!))")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
                .padding([.leading, .trailing], 10)
            }
            .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
        }
    }
}

extension View {
    func bottomStatusBar(cleanupModel: CleanupModel? = nil) -> some View {
        self.modifier(
            BottomStatusModifier(cleanupModel: cleanupModel)
        )
    }
}

/// Observe scan lifecycle and the completed total, without subscribing to per-file progress.
private struct CleanupStatusLink: View {
    let model: CleanupModel
    @SwiftUI.Environment(\.openWindow) private var openWindow
    @State private var availableBytes: UInt64?
    @State private var isScanning: Bool
    @State private var cleanupProgress: CleanupProgress?

    init(model: CleanupModel) {
        self.model = model
        _availableBytes = State(initialValue: model.availableCleanupBytes)
        _isScanning = State(initialValue: model.isScanning)
        _cleanupProgress = State(initialValue: model.cleanupProgress)
    }

    var body: some View {
        Button { openWindow(id: "cleanup") } label: {
            HStack(spacing: 6) {
                Image(systemName: (cleanupProgress?.failureCount ?? 0) > 0 ? "exclamationmark.triangle" : "externaldrive.badge.minus")
                if let cleanupProgress {
                    Text(cleanupProgress.statusText)
                } else if let availableBytes {
                    Text("Clean Up · ~\(ByteCountFormatter.string(fromByteCount: Int64(clamping: availableBytes), countStyle: .file))")
                } else {
                    Text("Clean Up")
                }
                if isScanning || cleanupProgress?.isFinished == false {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel(isScanning ? "Refreshing cleanup storage" : "Cleanup in progress")
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .help(cleanupProgress == nil ? "Open Clean Up to review storage." : "Open Clean Up to view progress or review failures. Cleanup continues when its window is closed.")
        .onReceive(model.$availableCleanupBytes.removeDuplicates()) { availableBytes = $0 }
        .onReceive(model.$isScanning.removeDuplicates()) { isScanning = $0 }
        .onReceive(model.$cleanupProgress.removeDuplicates()) { cleanupProgress = $0 }
    }
}

struct Previews_BottomStatusBar_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            HStack {

            }
            .bottomStatusBar()
            .environmentObject({ () -> AppState in
                let a = AppState()
                return a }()
            )
            .defaultAppStorage({ () -> UserDefaults in
                let d = UserDefaults(suiteName: "hide_support")!
                d.set(true, forKey: PreferenceKey.hideSupportXcodes.rawValue)
                return d
            }())

            HStack {

            }
            .bottomStatusBar()
            .environmentObject({ () -> AppState in
                let a = AppState()
                return a }()
            )
            .defaultAppStorage({ () -> UserDefaults in
                let d = UserDefaults(suiteName: "show_support")!
                d.set(false, forKey: PreferenceKey.hideSupportXcodes.rawValue)
                return d
            }())
        }
    }
}
