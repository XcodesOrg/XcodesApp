//
//  SelectedActionType.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2022-07-24.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation
public enum SelectedActionType: String, CaseIterable, Identifiable, CustomStringConvertible {
    case none
    case rename
    
    public var id: Self { self }
    
    public static var `default` = SelectedActionType.none
    
    public var description: String {
        switch self {
        case .none: return localizeString("OnSelectDoNothing")
        case .rename: return localizeString("OnSelectRenameXcode")
        }
    }
    
    public var detailedDescription: String {
        switch self {
        case .none: return localizeString("OnSelectDoNothingDescription")
        case .rename: return localizeString("OnSelectRenameXcodeDescription")
        }
    }
}
