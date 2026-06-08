//
//  SDKs+Xcode.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-06-05.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import XcodesKit

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
