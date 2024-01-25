//
//  BottomStatusBar.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2022-06-03.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation
import SwiftUI

struct BottomStatusModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text(appState.bottomStatusBarMessage)
                        .font(.subheadline)
                    Spacer()
                    Button(action: {
                        openURL(URL(string: "https://opencollective.com/xcodesapp")!)
                    }) {
                        HStack {
                            Image(systemName: "heart.circle")
                            Text("SponsorXcodes")
                        }
                    }
                    Text(Bundle.main.shortVersion!)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
                .padding([.leading, .trailing], 10)
            }
            .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
        }
    }
}

extension View {
    func bottomStatusBar() -> some View {
        self.modifier(
            BottomStatusModifier()
        )
    }
}

struct Previews_BottomStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
        
        }.bottomStatusBar()
    }
}
