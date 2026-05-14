//
//  SDKs+Xcode.swift
//  Rhodon
//
//  Created by Matt Kiazyk on 2023-06-05.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import Foundation
import SwiftUI
import RhodonKit

extension SDKs {
    /// Loops through all SDK's and returns an array of buildNumbers (to be used to correlate runtimes)
    func allBuilds() -> [String] {
        var buildNumbers: [String] = []

        if let iOS = iOS?.compactMap(\.build) {
            buildNumbers += iOS
        }
        if let tvOS = tvOS?.compactMap(\.build) {
            buildNumbers += tvOS
        }
        if let macOS = macOS?.compactMap(\.build) {
            buildNumbers += macOS
        }
        if let watchOS = watchOS?.compactMap(\.build) {
            buildNumbers += watchOS
        }
        if let visionOS = visionOS?.compactMap(\.build) {
            buildNumbers += visionOS
        }

        return buildNumbers
    }
}

extension DownloadableRuntime {
    func icon() -> Image {
        switch platform {
        case .iOS:
            Image(systemName: "iphone")
        case .macOS:
            Image(systemName: "macwindow")
        case .watchOS:
            Image(systemName: "applewatch")
        case .tvOS:
            Image(systemName: "appletv")
        case .visionOS:
            if #available(macOS 14, *) {
                Image(systemName: "visionpro")
            } else {
                Image(systemName: "eyeglasses")
            }
        }
    }
}
