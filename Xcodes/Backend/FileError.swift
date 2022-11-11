//
//  FileError.swift
//  Xcodes
//
//  Created by Leon Wolf on 06.10.22.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation
import LegibleError

enum FileError: LocalizedError{
    case fileNotFound(_ fileName: String)
}

extension FileError {
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let fileName):
            return String(format: localizeString("Alert.Uninstall.Error.Message.FileNotFound"), fileName)
        }
    }
}
