//
//  BillingNavigationActions.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/19.
//

import Foundation

import Foundation

struct PointsCenterNavigationActions {
    let showPointsLedger: () -> Void

    static let noop = PointsCenterNavigationActions(

        showPointsLedger: {}

    )

}

struct SubscriptionCenterNavigationActions {
    let showPointsCenter: () -> Void

    static let noop = SubscriptionCenterNavigationActions(

        showPointsCenter: {}

    )

}
