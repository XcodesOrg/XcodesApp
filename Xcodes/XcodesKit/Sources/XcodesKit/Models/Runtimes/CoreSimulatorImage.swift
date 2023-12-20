//
//  CoreSimulatorImage.swift
//  
//
//  Created by Matt Kiazyk on 2023-01-08.
//

import Foundation

public struct CoreSimulatorPlist: Decodable {
    public let images: [CoreSimulatorImage]
    
    public init(images: [CoreSimulatorImage]) {
        self.images = images
    }
}

public struct CoreSimulatorImage: Decodable, Identifiable, Equatable {
    public var id: String {
        return uuid
    }
    
    public let uuid: String
    public let path: [String: String]
    public let runtimeInfo: CoreSimulatorRuntimeInfo
    
    public init(uuid: String, path: [String : String], runtimeInfo: CoreSimulatorRuntimeInfo) {
        self.uuid = uuid
        self.path = path
        self.runtimeInfo = runtimeInfo
    }
    
    public static func == (lhs: CoreSimulatorImage, rhs: CoreSimulatorImage) -> Bool {
        lhs.id == rhs.id
    }
}

public struct CoreSimulatorRuntimeInfo: Decodable {
    public let build: String
    
    public init(build: String) {
        self.build = build
    }
}
