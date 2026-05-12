//
//  SDKs+Xcode.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-06-05.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import Foundation
import XcodesKit
import SwiftUI

extension SDKs {
    /// Loops through all SDK's and returns an array of buildNumbers (to be used to correlate runtimes)
    func allBuilds() -> [String] {
        var buildNumbers: [String] = []
        
        if let iOS = self.iOS?.compactMap({ $0.build }) {
            buildNumbers += iOS
        }
        if let tvOS = self.tvOS?.compactMap({ $0.build }) {
            buildNumbers += tvOS
        }
        if let macOS = self.macOS?.compactMap({ $0.build }) {
            buildNumbers += macOS
        }
        if let watchOS = self.watchOS?.compactMap({ $0.build }) {
            buildNumbers += watchOS
        }
        if let visionOS = self.visionOS?.compactMap({ $0.build }) {
            buildNumbers += visionOS
        }
        
        return buildNumbers
    }
}

extension DownloadableRuntime {
    func icon() -> Image {
        switch self.platform {
        case .iOS:
            return Image(systemName: "iphone")
        case .macOS:
            return Image(systemName: "macwindow")
        case .watchOS:
            return Image(systemName: "applewatch")
        case .tvOS:
            return Image(systemName: "appletv")
        case .visionOS:
            if #available(macOS 14, *) {
                return Image(systemName: "visionpro")
            } else {
                return Image(systemName: "eyeglasses")
            }
        }
    }
}
