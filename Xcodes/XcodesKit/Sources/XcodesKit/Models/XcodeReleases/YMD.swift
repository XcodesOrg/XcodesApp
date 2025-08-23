//
//  YMD.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/4/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public struct YMD: Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    
    public init(_ ymd: (Int, Int, Int)) {
        self.year = ymd.0; self.month = ymd.1; self.day = ymd.2
    }
    
    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year; self.month = month; self.day = day
    }
}
