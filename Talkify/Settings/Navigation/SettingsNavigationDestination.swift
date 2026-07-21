//
//  SettingsNavigationDestination.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import Foundation

enum SettingsNavigationDestination: Identifiable, Hashable {
    case detail(SettingsSection)
    
    var id: String {
        switch self {
        case .detail(let section):
            return section.rawValue
        }
    }
}
