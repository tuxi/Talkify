//
//  AppSheetRouter.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/31.
//

import SwiftUI

@MainActor
extension View {
    func withAppSheetDestinations(
        sheetDestinations: Binding<AppSheetDestination?>,
        container: AppContainer
    ) -> some View {
        sheet(item: sheetDestinations) { destination in
            switch destination {
            case .subscription:
                SubscriptionView(
                    container: container,
                    viewModel: SubscriptionViewModel(
                        billingManager: container.billingManager,
                        billingService: container.makeBillingService(),
                        authManager: container.authManager
                    )
                )
            }
        }
    }
}
