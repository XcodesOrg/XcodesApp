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

struct CompatibilityView_Preview: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var isNil = false
    var requiredMacOSVersion: String? {
        isNil 
        ? nil
        : "10.15.4"
    }

    var body: some View {
        VStack {
            HStack {
                CompatibilityView(requiredMacOSVersion: requiredMacOSVersion)
                    .border(.red)
            }
            Spacer()
            Toggle(isOn: $isNil) {
                Text("Is Nil?")
            }
        }
        .frame(width: 200, height: 100)
        .padding()
    }
}
