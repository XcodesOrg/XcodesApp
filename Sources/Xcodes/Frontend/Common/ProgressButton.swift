//
//  ProgressButton.swift
//  Xcodes
//
//  Created by Chad Sykes on 2020-12-27.
//  Copyright © 2020 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct ProgressButton<Label: View>: View {
    let isInProgress: Bool
    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            // This might look like a strange way to switch between the label and the progress view.
            // Doing it this way, so that the label is hidden but still has the same frame and is in the view hierarchy
            // makes sure that the button's frame doesn't change when isInProgress changes.
            label()
                .isHidden(isInProgress)
                .overlay(
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(x: 0.5, y: 0.5, anchor: .center)
                        .isHidden(!isInProgress)
                )
        }
        .disabled(isInProgress)
    }
}
