//
//  NotInstalledStateButtonsView.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import Version

struct NotInstalledStateButtons: View {
    let downloadFileSizeString: String?
    let id: Version

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                appState.checkMinVersionAndInstall(id: id)
            } label: {
                Text("Install") .help("Install")
            }
            
            if let size = downloadFileSizeString {
                Text("DownloadSize")
                    .font(.headline)
                Text(size)
                    .font(.subheadline)
            } else {
                EmptyView()
            }
        }
    }
}

struct NotInstalledStateButtons_Preview: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var isSizeNil = false

    var downloadFileSizeString: String? {
        isSizeNil
        ? nil
        : "1,19 GB"
    }

    var body: some View {
        VStack {
            NotInstalledStateButtons(
                downloadFileSizeString: downloadFileSizeString,
                id: Version(major: 12, minor: 3, patch: 0)
            )
            .border(.red)
            Spacer()
            Toggle(isOn: $isSizeNil) {
                Text("Is Size Nil?")
            }
        }
        .frame(width: 200, height: 100)
        .padding()
    }
}
