//
//  SettingsSheetDestination.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import SwiftUI

enum SettingsSheetDestination: Identifiable, Hashable {
    case demo
    
    var id: String {
        switch self {
        case .demo:
            return "demo"
        }
    }
}

enum SettingsCoverDestination: Identifiable, Hashable {
    case demo
    
    var id: String {
        switch self {
        case .demo:
            return "demo"
        }
    }
}
