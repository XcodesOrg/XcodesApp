//
//  BottomStatusBar.swift
//  Rhodon
//
//  Created by Matt Kiazyk on 2022-06-03.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation
import SwiftUI

struct BottomStatusModifier: ViewModifier {
    @SwiftUI.Environment(AppState.self) private var appState
    @AppStorage(PreferenceKey.hideSupportRhodon.rawValue) var hideSupportRhodon = false

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
                    if !hideSupportRhodon {
                        Button(action: {
                            openURL(URL(string: "https://opencollective.com/rhodonapp")!)
                        }, label: {
                            HStack {
                                Image(systemName: "heart.circle")
                                Text("Support Rhodon")
                            }
                        })
                    }
                    Text(verbatim: "\(Bundle.main.shortVersion!) (\(Bundle.main.version!))")
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
        modifier(
            BottomStatusModifier()
        )
    }
}

struct BottomStatusBarPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            HStack {}
                .bottomStatusBar()
                .environment({ () -> AppState in
                    return AppState()
                }())
                .defaultAppStorage({ () -> UserDefaults in
                    let userDefaults = UserDefaults(suiteName: "hide_support")!
                    userDefaults.set(true, forKey: PreferenceKey.hideSupportRhodon.rawValue)
                    return userDefaults
                }())

            HStack {}
                .bottomStatusBar()
                .environment({ () -> AppState in
                    return AppState()
                }())
                .defaultAppStorage({ () -> UserDefaults in
                    let userDefaults = UserDefaults(suiteName: "show_support")!
                    userDefaults.set(false, forKey: PreferenceKey.hideSupportRhodon.rawValue)
                    return userDefaults
                }())
        }
    }
}
