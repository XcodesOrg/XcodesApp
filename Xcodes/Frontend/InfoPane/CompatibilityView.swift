//
//  CompatibilityView.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct CompatibilityView: View {
    let requiredMacOSVersion: String?

    var body: some View {
        if let requiredMacOSVersion = requiredMacOSVersion {
            VStack(alignment: .leading) {
                Text("Compatibility")
                    .font(.headline)
                Text(String(format: localizeString("MacOSRequirement"), requiredMacOSVersion))
                    .font(.subheadline)
            }
        } else {
            EmptyView()
        }
    }
}

#Preview {
  CompatibilityView(requiredMacOSVersion: "10.15.4")
    .padding()
}
