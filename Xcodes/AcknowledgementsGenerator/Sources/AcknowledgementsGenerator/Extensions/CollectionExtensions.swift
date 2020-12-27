//
//  CollectionExtensions.swift
//  spm-licenses
//
//  Created by Sergii Kryvoblotskyi on 11/11/19.
//  Copyright © 2019 MacPaw. All rights reserved.
//

import Foundation

public extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
