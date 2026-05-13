//
//  SDKs.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/4/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public struct SDKs: Codable {
    public let macOS: [XcodeVersion]?
    public let iOS: [XcodeVersion]?
    public let watchOS: [XcodeVersion]?
    public let tvOS: [XcodeVersion]?
    public let visionOS: [XcodeVersion]?

    public init(
        macOS: XcodeVersion? = nil,
        iOS: XcodeVersion? = nil,
        watchOS: XcodeVersion? = nil,
        tvOS: XcodeVersion? = nil,
        visionOS: XcodeVersion? = nil
    ) {
        self.macOS = macOS.map { [$0] }
        self.iOS = iOS.map { [$0] }
        self.watchOS = watchOS.map { [$0] }
        self.tvOS = tvOS.map { [$0] }
        self.visionOS = visionOS.map { [$0] }
    }

    public init(
        macOS: [XcodeVersion]?,
        iOS: XcodeVersion? = nil,
        watchOS: XcodeVersion? = nil,
        tvOS: XcodeVersion? = nil,
        visionOS: XcodeVersion? = nil
    ) {
        self.macOS = macOS?.isEmpty == true ? nil : macOS
        self.iOS = iOS.map { [$0] }
        self.watchOS = watchOS.map { [$0] }
        self.tvOS = tvOS.map { [$0] }
        self.visionOS = visionOS.map { [$0] }
    }

    public init(
        macOS: [XcodeVersion]?,
        iOS: [XcodeVersion]?,
        watchOS: XcodeVersion? = nil,
        tvOS: XcodeVersion? = nil,
        visionOS: XcodeVersion? = nil
    ) {
        self.macOS = macOS?.isEmpty == true ? nil : macOS
        self.iOS = iOS?.isEmpty == true ? nil : iOS
        self.watchOS = watchOS.map { [$0] }
        self.tvOS = tvOS.map { [$0] }
        self.visionOS = visionOS.map { [$0] }
    }

    public init(
        macOS: [XcodeVersion]?,
        iOS: [XcodeVersion]?,
        watchOS: [XcodeVersion]?,
        tvOS: XcodeVersion? = nil,
        visionOS: XcodeVersion? = nil
    ) {
        self.macOS = macOS?.isEmpty == true ? nil : macOS
        self.iOS = iOS?.isEmpty == true ? nil : iOS
        self.watchOS = watchOS?.isEmpty == true ? nil : watchOS
        self.tvOS = tvOS.map { [$0] }
        self.visionOS = visionOS.map { [$0] }
    }

    public init(
        macOS: [XcodeVersion]?,
        iOS: [XcodeVersion]?,
        watchOS: [XcodeVersion]?,
        tvOS: [XcodeVersion]?,
        visionOS: [XcodeVersion]?
    ) {
        self.macOS = macOS?.isEmpty == true ? nil : macOS
        self.iOS = iOS?.isEmpty == true ? nil : iOS
        self.watchOS = watchOS?.isEmpty == true ? nil : watchOS
        self.tvOS = tvOS?.isEmpty == true ? nil : tvOS
        self.visionOS = visionOS?.isEmpty == true ? nil : visionOS
    }
}
