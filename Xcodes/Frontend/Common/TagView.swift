//
//  TagView.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2025-06-25.//


import SwiftUI

struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.quaternary)
            )
    }
}
