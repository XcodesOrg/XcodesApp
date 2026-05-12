//
//  Collection+.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2022-04-11.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation

public extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
