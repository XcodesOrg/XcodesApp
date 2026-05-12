//
//  Checksums.swift
//  xcodereleases
//
//  Created by Xcode Releases on 9/17/20.
//  Copyright © 2020 Xcode Releases. All rights reserved.
//


import Foundation

public struct Checksums: Codable {
    
    public let sha1: String?
    
    public init(sha1: String? = nil) {
        self.sha1 = sha1
    }
    
}
