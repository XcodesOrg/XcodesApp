//
//  RuntimeArchitecture.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2025-07-07.
//

enum RuntimeArchitecture: String, CaseIterable, Identifiable {
    case arm64
    case x86_64
    
    var id: Self { self }
    
    var displayValue: String {
        return rawValue
    }
}
