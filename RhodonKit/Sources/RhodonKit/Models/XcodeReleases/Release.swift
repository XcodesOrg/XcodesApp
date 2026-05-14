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
        case gmRelease = "gm"
        case gmSeed
        case releaseCandidate = "rc"
        case beta
        case developerPreview = "dp"
        case release
    }

    public var isGM: Bool {
        guard case .gmRelease = self else { return false }
        return true
    }

    case gmRelease
    case gmSeed(Int)
    case releaseCandidate(Int)
    case beta(Int)
    case developerPreview(Int)
    case release

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .gmRelease) != nil {
            self = .gmRelease
        } else if let version = try container.decodeIfPresent(Int.self, forKey: .gmSeed) {
            self = .gmSeed(version)
        } else if let version = try container.decodeIfPresent(Int.self, forKey: .releaseCandidate) {
            self = .releaseCandidate(version)
        } else if let version = try container.decodeIfPresent(Int.self, forKey: .beta) {
            self = .beta(version)
        } else if let version = try container.decodeIfPresent(Int.self, forKey: .developerPreview) {
            self = .developerPreview(version)
        } else if try container.decodeIfPresent(Bool.self, forKey: .release) != nil {
            self = .release
        } else {
            fatalError("Unreachable")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .gmRelease: try container.encode(true, forKey: .gmRelease)
        case let .gmSeed(version): try container.encode(version, forKey: .gmSeed)
        case let .releaseCandidate(version): try container.encode(version, forKey: .releaseCandidate)
        case let .beta(version): try container.encode(version, forKey: .beta)
        case let .developerPreview(version): try container.encode(version, forKey: .developerPreview)
        case .release: try container.encode(true, forKey: .release)
        }
    }
}
