//
//  SubscriptionRoute.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/19.
//

import SwiftUI
import CoreKit
import AgentKit

enum SubscriptionRoute: Hashable, Identifiable {
    case pointsCenter
    case pointsLedger
    case subscriptionCenter
    case openURL(_ url: URL)

    var id: String {
        switch self {
        case .pointsCenter:
            return "pointsCenter"
        case .pointsLedger:
            return "pointsLedger"
        case .subscriptionCenter:
            return "subscriptionCenter"
        case .openURL(let url):
            return url.absoluteString
        }
    }
}

@MainActor
extension View {
    func withSubscriptionNavigationDestinations(
        container: AppContainer,
        router: SubscriptionRouter
    ) -> some View {
        navigationDestination(for: SubscriptionRoute.self) { destination in
            switch destination {
            case .pointsCenter:
                PointsCenterView(
                    viewModel: PointsCenterViewModel(
                        billingManager: container.billingManager,
                        billingService: container.makeBillingService()
                    )
                )
                .injectSubscriptionContext(container: container, router: router)

            case .pointsLedger:
                PointsLedgerView(
                    viewModel: PointsLedgerViewModel(
                        billingService: container.makeBillingService()
                    )
                )
                .injectSubscriptionContext(container: container, router: router)

            case .subscriptionCenter:
                SubscriptionCenterView(
                    navigationActions: SubscriptionCenterNavigationActions(
                        showPointsCenter: {
                            router.navigate(to: .pointsCenter)
                        }
                    ),
                    viewModel: SubscriptionCenterViewModel(
                        billingManager: container.billingManager,
                        billingService: container.makeBillingService()
                    )
                )
                .injectSubscriptionContext(container: container, router: router)
            case .openURL(let url):
                BrowserView(url: url)
            }
        }
    }
}

@MainActor
extension View {
    func injectSubscriptionContext(
        container: AppContainer,
        router: SubscriptionRouter
    ) -> some View {
        self
            .environment(router)
            .environment(container)
            .environment(container.authManager)
            .environment(container.userManager)
            .environment(container.billingManager)
    }
}
