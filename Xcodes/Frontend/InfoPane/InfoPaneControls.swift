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
                HStack {
                    Spacer()
                    NotInstalledStateButtons(
                        downloadFileSizeString: xcode.downloadFileSizeString,
                        id: xcode.id)
                }
                
            case .installing(let installationStep):
                HStack(alignment: .top) {
                    InstallationStepDetailView(installationStep: installationStep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CancelInstallButton(xcode: xcode)
                }
            case .installed(_):
                InstalledStateButtons(xcode: xcode)
            }
        }
    }
}

#Preview(XcodePreviewName.allCases[0].rawValue) { makePreviewContent(for: 0) }
#Preview(XcodePreviewName.allCases[1].rawValue) { makePreviewContent(for: 1) }
#Preview(XcodePreviewName.allCases[2].rawValue) { makePreviewContent(for: 2) }
#Preview(XcodePreviewName.allCases[3].rawValue) { makePreviewContent(for: 3) }
#Preview(XcodePreviewName.allCases[4].rawValue) { makePreviewContent(for: 4) }
#Preview(XcodePreviewName.allCases[5].rawValue) { makePreviewContent(for: 5) }

private func makePreviewContent(for index: Int) -> some View {
  let name = XcodePreviewName.allCases[index]

  return InfoPaneControls(xcode: xcodeDict[name]!)
    .environmentObject(configure(AppState()) {
      $0.allXcodes = [xcodeDict[name]!]
    })
    .frame(width: 500)
    .padding()
}
