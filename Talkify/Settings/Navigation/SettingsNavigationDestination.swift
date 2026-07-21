//
//  SettingsNavigationDestination.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import Foundation

enum SettingsNavigationDestination: Identifiable, Hashable {
    case general
    case profile
    case usage
    case account
    
    var id: String {
        switch self {
        case .general:
            return "general"
        case .profile:
            return "profile"
        case .usage:
            return "usage"
        case .account:
            return "account"
        }
    }
}
