//
//  IconView.swift
//  Xcodes
//
//  Created by Duong Thai on 11/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import Path

struct IconView: View {
    let installState: XcodeInstallState

    var body: some View {
        if case let .installed(path) = installState {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.string))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }
}

#Preview("Installed") {
  IconView(installState: XcodeInstallState.installed(Path("/Applications/Xcode.app")!))
    .frame(width: 300, height: 100)
    .padding()
}

#Preview("Not Installed") {
  IconView(installState: XcodeInstallState.notInstalled)
    .frame(width: 300, height: 100)
    .padding()
}
