//
//  IconView.swift
//  Xcodes
//
//  Created by Duong Thai on 11/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import Path
import SwiftUI
import Version

struct IconView: View {
    let xcode: Xcode

    var body: some View {
        if case let .installed(path) = xcode.installState {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.string))
        } else {
            Image(xcode.version.isPrerelease ? "xcode-beta" : "xcode")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }
}

#Preview("Installed") {
    IconView(xcode: Xcode(version: Version("12.3.0")!, installState: .installed(Path("/Applications/Xcode-12.3.0.app")!), selected: true, icon: nil))
        .frame(width: 300, height: 100)
        .padding()
}

#Preview("Installed") {
    IconView(xcode: Xcode(version: Version("12.3.0")!, installState: .notInstalled, selected: true, icon: nil))
        .frame(width: 300, height: 100)
        .padding()
}

#Preview("Not Installed") {
    IconView(xcode: Xcode(version: Version("12.0.0-1234A")!, installState: .notInstalled, selected: false, icon: nil))
        .frame(width: 300, height: 100)
        .padding()
}
