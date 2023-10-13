//
//  InstallingStateButtons.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import Version
import XCModel
import Path

struct InstalledStateButtons: View {
    let xcode: Xcode

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(xcode.installedPath?.string ?? "")
                Button(action: { appState.reveal(xcode.installedPath) }) {
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
    }
}

struct InstalledStateButtons_Preview: PreviewProvider {
    static var previews: some View {
        InstalledStateButtons(xcode: Self.xcode)
            .environmentObject(configure(AppState()) {
                $0.allXcodes = [Self.xcode]
            })
            .padding()
            .frame(width: 300)
    }

    static private let xcode = Xcode(
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
}

