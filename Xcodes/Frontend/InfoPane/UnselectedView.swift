//
//  UnselectedView.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct UnselectedView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("NoXcodeSelected")
                .font(.title)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct UnselectedView_Preview: PreviewProvider {
    static var previews: some View {
        UnselectedView()
            .padding()
    }
}
