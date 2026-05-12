//
//  Link.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/5/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public struct Link: Codable {
    public let url: URL
    public let sizeMB: Int?
    /// The platforms supported by this link, if applicable.
    public var architectures: [Architecture]?

//    public init(_ string: String, _ size: Int? = nil, _ architectures: [Architecture]? = nil) {
//        self.url = URL(string: string)!
//        self.sizeMB = size
//        self.architectures = architectures
//    }
}

public struct Links: Codable {
    public let download: Link?
    public let notes: Link?
    
    public init(download: Link? = nil, notes: Link? = nil) {
        self.download = download
        self.notes = notes
    }
}
