//
//  TrailingIconLabelStyle.swift
//  Xcodes
//
//  Created by Daniel Chick on 3/11/24.
//  Copyright © 2024 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.title
            configuration.icon
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: Self { Self() }
}
