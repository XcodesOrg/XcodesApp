//
//  CompatibilityView.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct CompatibilityView: View {
    @EnvironmentObject var appState: AppState
    
    let requiredMacOSVersion: String?

    var body: some View {
        if let requiredMacOSVersion = requiredMacOSVersion {
            HStack(alignment: .top){
                VStack(alignment: .leading) {
                    Text("Compatibility")
                        .font(.headline)
                    Text(String(format: localizeString("MacOSRequirement"), requiredMacOSVersion))
                        .font(.subheadline)
                        .foregroundColor(appState.hasMinSupportedOS(requiredMacOSVersion: requiredMacOSVersion) ? .red : .primary)
                }
                Spacer()
                if appState.hasMinSupportedOS(requiredMacOSVersion: requiredMacOSVersion) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            EmptyView()
        }
    }
}

#Preview {
  CompatibilityView(requiredMacOSVersion: "10.15.4")
    .padding()
    .environmentObject(AppState())
}
