//
//  CoreSimulatorImage.swift
//  
//
//  Created by Matt Kiazyk on 2023-01-08.
//

import Foundation

public struct CoreSimulatorPlist: Decodable {
    public let images: [CoreSimulatorImage]
}

public struct CoreSimulatorImage: Decodable {
    public let uuid: String
    public let runtimeInfo: CoreSimulatorRuntimeInfo
}

public struct CoreSimulatorRuntimeInfo: Decodable {
    public let build: String
}
