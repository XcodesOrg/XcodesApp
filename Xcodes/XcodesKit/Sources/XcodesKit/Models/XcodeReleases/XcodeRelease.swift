//
//  Xcode.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/3/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public struct XcodeRelease: Codable {
    public let name: String
    public let version: XcodeVersion
    public let date: YMD
    public let requires: String
    public let sdks: SDKs?
    public let compilers: Compilers?
    public let links: Links?
    public let checksums: Checksums?
    
    public var architectures: [Architecture]? {
        return links.flatMap { $0.download?.architectures }
    }
    
    public init(name: String = "Xcode", version: XcodeVersion, date: (Int, Int, Int), requires: String, sdks: SDKs? = nil, compilers: Compilers? = nil, links: Links? = nil, checksums: Checksums? = nil) {
        self.name = name
        self.version = version;
        self.date = YMD(date);
        self.requires = requires;
        self.sdks = sdks;
        self.compilers = compilers
        self.links = links
        self.checksums = checksums
    }
}
