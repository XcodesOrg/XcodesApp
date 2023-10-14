//
//  InfoPaneControls.swift
//  Xcodes
//
//  Created by Duong Thai on 14/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct InfoPaneControls: View {
    let xcode: Xcode

    var body: some View {
        VStack (alignment: .leading) {
            switch xcode.installState {
            case .notInstalled:
                NotInstalledStateButtons(
                    downloadFileSizeString: xcode.downloadFileSizeString,
                    id: xcode.id)
            case .installing(let installationStep):
                InstallationStepDetailView(installationStep: installationStep)
                CancelInstallButton(xcode: xcode)
            case .installed(_):
                InstalledStateButtons(xcode: xcode)
            }
        }
    }
}

struct InfoPaneControls_Previews: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var name: PreviewName = .Populated_Installed_Selected

    var body: some View {
        VStack {
            InfoPaneControls(xcode: xcode)
                .environmentObject(configure(AppState()) {
                    $0.allXcodes = [xcode]
                })
                .border(.red)
                .frame(width: 300, height: 400)
            Spacer()
            Picker("Preview Name", selection: $name) {
                ForEach(PreviewName.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.inline)

        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    var xcode: Xcode { xcodeDict[name]! }
}
