//
//  Release.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/4/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public enum Release: Codable {
    
    public enum CodingKeys: String, CodingKey {
        case gm, gmSeed, rc, beta, dp, release
    }
    
    public var isGM: Bool {
        guard case .gm = self else { return false }
        return true
    }
    
    case gm
    case gmSeed(Int)
    case rc(Int)
    case beta(Int)
    case dp(Int)
    case release
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let _ = try container.decodeIfPresent(Bool.self, forKey: .gm) {
            self = .gm
        } else if let v = try container.decodeIfPresent(Int.self, forKey: .gmSeed) {
            self = .gmSeed(v)
        } else if let v = try container.decodeIfPresent(Int.self, forKey: .rc) {
            self = .rc(v)
        } else if let v = try container.decodeIfPresent(Int.self, forKey: .beta) {
            self = .beta(v)
        } else if let v = try container.decodeIfPresent(Int.self, forKey: .dp) {
            self = .dp(v)
        } else if let _ = try container.decodeIfPresent(Bool.self, forKey: .release) {
            self = .release
        } else {
            fatalError("Unreachable")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .gm: try container.encode(true, forKey: .gm)
        case .gmSeed(let v): try container.encode(v, forKey: .gmSeed)
        case .rc(let v): try container.encode(v, forKey: .rc)
        case .beta(let v): try container.encode(v, forKey: .beta)
        case .dp(let v): try container.encode(v, forKey: .dp)
        case .release: try container.encode(true, forKey: .release)
        }
    }
}
