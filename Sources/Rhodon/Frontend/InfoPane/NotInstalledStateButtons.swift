//
//  NotInstalledStateButtons.swift
//  Rhodon
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import Version
import RhodonKit

struct NotInstalledStateButtons: View {
    let downloadFileSizeString: String?
    let id: XcodeID

    @SwiftUI.Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                appState.checkMinVersionAndInstall(id: id)
            } label: {
                if id.architectures?.isAppleSilicon ?? false {
                    Text("Install Apple Silicon").help("Install")
                } else {
                    Text("Install Universal").help("Install")
                }
            }

            if let size = downloadFileSizeString {
                Text("Download Size")
                    .font(.headline)
                Text(size)
                    .font(.subheadline)
            }
        }
    }
}

#Preview {
    NotInstalledStateButtons(
        downloadFileSizeString: "1,19 GB",
        id: XcodeID(version: Version(major: 12, minor: 3, patch: 0), architectures: nil)
    )
    .padding()
}
