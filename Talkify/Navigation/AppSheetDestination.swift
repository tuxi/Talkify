//
//  AppSheetDestination.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/31.
//

import Foundation

enum AppSheetDestination: Identifiable, Equatable {
    case subscription
    
    var id: String {
        switch self {
        case .subscription:
            return "subscription"
        }
    }

    static func == (lhs: AppSheetDestination, rhs: AppSheetDestination) -> Bool {
        lhs.id == rhs.id
    }
}
