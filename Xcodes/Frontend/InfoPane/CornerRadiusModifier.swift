//
//  CornerRadiusModifier.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-12-19.
//

import Foundation
import SwiftUI

struct CornerRadiusModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

extension View {
    func xcodesBackground() -> some View {
        self.modifier(
            CornerRadiusModifier()
        )
    }
}

struct Previews_CornerRadius_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            Text(verbatim: "XCODES RULES!")
        }.xcodesBackground()
    }
}
