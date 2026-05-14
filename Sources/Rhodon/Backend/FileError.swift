//
//  FileError.swift
//  Rhodon
//
//  Created by Leon Wolf on 06.10.22.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation

enum FileError: LocalizedError {
    case fileNotFound(_ fileName: String)
}

extension FileError {
    var errorDescription: String? {
        switch self {
        case let .fileNotFound(fileName):
            "Could not find file \"\(fileName)\"."
        }
    }
}

private let theOperationCouldNotBeCompleted = "The operation couldn\u{2019}t be completed."

extension Error {
    var legibleDescription: String {
        switch errorType {
        case .swiftError(.enum?), .swiftLocalizedError(_, .enum?):
            return "\(type(of: self)).\(self)"
        case .swiftError(.class?), .swiftLocalizedError(_, .class?):
            return "\(type(of: self))"
        case .swiftError, .swiftLocalizedError:
            return String(describing: self)
        case let .nsError(nsError, domain, code):
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                return "\(domain)(\(code), \(underlyingError.domain)(\(underlyingError.code)))"
            } else {
                return "\(domain)(\(code))"
            }
        }
    }

    var legibleLocalizedDescription: String {
        switch errorType {
        case .swiftError:
            return "\(theOperationCouldNotBeCompleted) (\(legibleDescription))"
        case let .swiftLocalizedError(message, _):
            return message
        case .nsError(_, "kCLErrorDomain", 0):
            return "The location could not be determined."
        case let .nsError(nsError, domain, code):
            if !localizedDescription.hasPrefix(theOperationCouldNotBeCompleted) {
                return localizedDescription
            } else if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                return underlyingError.legibleLocalizedDescription
            } else {
                return "\(theOperationCouldNotBeCompleted) (\(domain).\(code))"
            }
        }
    }

    private var errorType: LegibleErrorType {
        let value: Any = self
        let nativeClassNames = ["_SwiftNativeNSError", "__SwiftNativeNSError"]
        let selfClassName = String(cString: object_getClassName(self))
        let isNSError = !nativeClassNames.contains(selfClassName) && value is NSObject

        if isNSError {
            let nsError = self as NSError
            return .nsError(nsError, domain: nsError.domain, code: nsError.code)
        } else if let error = self as? LocalizedError, let message = error.errorDescription {
            return .swiftLocalizedError(message, Mirror(reflecting: self).displayStyle)
        } else {
            return .swiftError(Mirror(reflecting: self).displayStyle)
        }
    }
}

private enum LegibleErrorType {
    case nsError(NSError, domain: String, code: Int)
    case swiftLocalizedError(String, Mirror.DisplayStyle?)
    case swiftError(Mirror.DisplayStyle?)
}
