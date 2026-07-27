//
//  SettingsRouterViewModifiers.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import SwiftUI

@MainActor
extension View {
   
    func withSettingsNavigationDestinations(
            router: SettingsRouter,
            container: AppContainer
    ) -> some View {
        navigationDestination(for: SettingsNavigationDestination.self) { destination in
            switch destination {
            case .detail(let section):
                SettingsDetailView(section: section)
            case .pointsCenter:
                PointsCenterView(viewModel: PointsCenterViewModel(billingManager: container.billingManager, billingService: container.makeBillingService()))
                    .environment(router)
            case .subscriptionCenter:
                SubscriptionCenterView(navigationActions: SubscriptionCenterNavigationActions(showPointsCenter: {
                    
                }), viewModel: SubscriptionCenterViewModel(
                    billingManager: container.billingManager,
                    billingService: container.makeBillingService()
                ))
            case .pointsLedgerView:
                PointsLedgerView(viewModel: PointsLedgerViewModel(billingService: container.makeBillingService()))
            }
        }
    }
    
   func withSettingsSheetDestinations(
        sheetDestinations: Binding<SettingsSheetDestination?>,
        container: AppContainer
    ) -> some View {
        return sheet(item: sheetDestinations) { destination in
            switch destination {
            case .subscription:
                SubscriptionView(container: container, viewModel: SubscriptionViewModel(billingManager: container.billingManager, billingService: container.makeBillingService(), authManager: container.authManager))
            }
        }
    }
    
   func withSettingsCoverDestinations(
        coverDestinations: Binding<SettingsCoverDestination?>
    ) -> some View {
        // 使用一个统一的辅助方法来渲染内容
        let sheetContent = { (destination: SettingsCoverDestination) -> AnyView in
            let view: AnyView
            switch destination {
            case .demo:
                view = AnyView(Color.blue)
            }
            return view
        }
        
#if os(macOS)
        return sheet(item: coverDestinations) {
            sheetContent($0)
                .frame(minWidth: 600, minHeight: 450) // macOS 需要给个默认大小
        }
#else
        return fullScreenCover(item: coverDestinations, content: sheetContent)
#endif
    }
}
