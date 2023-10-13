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

//#Preview {
//    Group {
//        IconView(path: "/Applications/Xcode.app")
//        IconView()
//    }
//    .padding()
//}

struct IconView_Preview: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var isIcon = false
    var state: XcodeInstallState {
        isIcon 
        ? XcodeInstallState.notInstalled
        : XcodeInstallState.installed(Path("/Applications/Xcode.app")!)
    }

    var body: some View {
        VStack {
            HStack {
                IconView(installState: state)
                    .border(.red)
            }
            Spacer()
            Toggle(isOn: $isIcon) {
                Text("Is an Icon?")
            }
        }
        .animation(.default)
        .frame(width: 300, height: 100)
        .padding()
    }
}
