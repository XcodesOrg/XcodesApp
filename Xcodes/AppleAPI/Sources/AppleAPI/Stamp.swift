//
//  Stamp.swift
//  
//
//  Created by Matt Kiazyk on 2023-02-23.
//

import Foundation

public struct Stamp {

    private static let DateFormatWithoutTime = "yyMMdd"
    private static let DateFormatWithTime = "yyMMddHHmmss"

    public let version : UInt
    public let date : Date
    public let resource : String

    // Version 1 only
    public var claim : UInt?
    public var counter : String?
    public var ext : String?
    public var random : String?

    // Version 0 only
    public var suffix : String?

    init?(stamp: String) {
        let components = stamp.components(separatedBy: ":")

        if (components.count < 1) {
            print("No stamp components. Ensure it is separated by a `:`")
            return nil
        }

        guard let version = UInt(components[0]) else {
            print("Unable to parse stamp version")
            return nil
        }

        self.version = version

        if self.version > 1 {
            print("Version > 1. Not handled")
            return nil
        }

        if (self.version == 0 && components.count < 4) {
            print("Not enough components for version 0")
            return nil
        }

        if (self.version == 1 && components.count < 7) {
            print("Not enough components for version 1")
            return nil
        }

        if (self.version == 0) {
            if let date = Stamp.parseDate(dateString: components[1]) {
                self.date = date
            } else {
                return nil
            }
            self.resource = components[2]
            self.suffix = components[3]
        } else if (self.version == 1) {
            if let claim =  UInt(components[1]) {
                self.claim = claim
            }
            if let date = Stamp.parseDate(dateString: components[2]) {
                self.date = date
            } else {
                return nil
            }
            self.resource = components[3]
            self.ext = components[4]
            self.random = components[5]
            self.counter = components[6]
        } else {
            return nil
        }
    }

    private static func parseDate(dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = Stamp.DateFormatWithoutTime

        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.dateFormat = Stamp.DateFormatWithTime

        if let date = formatter.date(from: dateString) {
            return date
        } else {
            print("Unable to parse date")
            return nil
        }
    }
}
