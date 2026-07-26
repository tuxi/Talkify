//
//  AppGlobalCoverDestination.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/19.
//

import Foundation

enum AppGlobalCoverDestination: Identifiable, Equatable {
    case subscription
    case auth

    var id: String {
        switch self {
        case .subscription:
            return "global_subscription"
        case .auth:
            return "auth"
        }
    }

    static func == (lhs: AppGlobalCoverDestination, rhs: AppGlobalCoverDestination) -> Bool {
        lhs.id == rhs.id
    }
}
