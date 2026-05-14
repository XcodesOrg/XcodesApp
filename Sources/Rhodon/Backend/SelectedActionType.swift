//
//  SelectedActionType.swift
//  Rhodon
//
//  Created by Matt Kiazyk on 2022-07-24.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation

public enum SelectedActionType: String, CaseIterable, Identifiable, CustomStringConvertible, Sendable {
    case none
    case rename

    public var id: Self {
        self
    }

    public static let `default` = SelectedActionType.none

    public var description: String {
        switch self {
        case .none: "Keep name as Xcode-X.X.X.app"
        case .rename: "Always rename to Xcode.app"
        }
    }

    public var detailedDescription: String {
        switch self {
        case .none: "On select, will keep the name as the version eg. Xcode-13.4.1.app"
        case .rename:
            // swiftlint:disable:next line_length
            "On select, will automatically try and rename the active Xcode to Xcode.app, renaming the previous Xcode.app to the version name."
        }
    }
}
