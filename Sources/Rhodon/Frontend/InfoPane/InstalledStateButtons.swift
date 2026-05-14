//
//  InstalledStateButtons.swift
//  Rhodon
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import Path
import SwiftUI
import Version
import RhodonKit

struct InstalledStateButtons: View {
    let xcode: Xcode

    @SwiftUI.Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(xcode.installedPath?.string ?? "")
                Button(action: { appState.reveal(xcode.installedPath) }, label: {
                    Image(systemName: "arrow.right.circle.fill")
                })
                .buttonStyle(PlainButtonStyle())
                .help("Reveal in Finder")
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

#Preview {
    InstalledStateButtons(xcode: xcode)
        .environment(configure(AppState()) {
            $0.allXcodes = [xcode]
        })
        .padding()
        .frame(width: 300)
}

@MainActor
private let xcode = Xcode(
    version: Version(major: 12, minor: 3, patch: 0),
    installState: .installed(Path("/Applications/Xcode-12.3.0.app")!),
    selected: true,
    icon: NSWorkspace.shared.icon(forFile: "/Applications/Xcode-12.3.0.app"),
    requiredMacOSVersion: "10.15.4",
    releaseNotesURL: URL(
        string: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_3-release-notes/"
    )!,
    releaseDate: Date(),
    sdks: SDKs(
        macOS: .init(number: "11.1"),
        iOS: .init(number: "14.3"),
        watchOS: .init(number: "7.3"),
        tvOS: .init(number: "14.3")
    ),
    compilers: Compilers(
        gcc: .init(number: "4"),
        llvmGcc: .init(number: "213"),
        llvm: .init(number: "2.3"),
        clang: .init(number: "7.3"),
        swift: .init(number: "5.3.2")
    ),
    downloadFileSize: 242_342_424
)
