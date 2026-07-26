//
//  AppCoverDestination.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/31.
//

import Foundation
import CoreGraphics
import CoreKit

enum AppCoverDestination: Identifiable, Equatable {
    
    case subscription

    var id: String {
        switch self {
        case .subscription:
            return "subscription"
        }
    }

    static func == (lhs: AppCoverDestination, rhs: AppCoverDestination) -> Bool {
        lhs.id == rhs.id
    }
}
