//
//  String+.swift
//  Xcodes
//
//  Created by Jinyu Meng on 2024/01/20.
//  Copyright © 2024 Robots and Pencils. All rights reserved.
//

import Foundation

extension String {
    // Declare String as String explicitly. Prevent it from being recognized as a LocalizedStringKey.
    var hideInLocalizations: String {
        return String(self)
    }
}
