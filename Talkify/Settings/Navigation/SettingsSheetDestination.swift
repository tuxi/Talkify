//
//  SettingsSheetDestination.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import SwiftUI

enum SettingsSheetDestination: Identifiable, Equatable {
    case demo
    
    var id: String {
        switch self {
        case .demo:
            return "demo"
        }
    }

    static func == (lhs: SettingsSheetDestination, rhs: SettingsSheetDestination) -> Bool {
        lhs.id == rhs.id
    }
}

enum SettingsCoverDestination: Identifiable, Equatable {
    case demo
    
    var id: String {
        switch self {
        case .demo:
            return "demo"
        }
    }

    static func == (lhs: SettingsCoverDestination, rhs: SettingsCoverDestination) -> Bool {
        lhs.id == rhs.id
    }
}
