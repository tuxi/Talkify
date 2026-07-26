//
//  AppCoverRouter.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/31.
//


import SwiftUI
import AgentKit
import CoreKit
import DesignKit

@MainActor
extension View {
    func withAppCoverDestinations(
        coverDestinations: Binding<AppCoverDestination?>,
        container: AppContainer,
    ) -> some View {
        let coverContent = { (destination: AppCoverDestination) -> AnyView in
            let view: AnyView
            switch destination {
            case .subscription:
                view = AnyView(
                    SubscriptionView(
                        container: container,
                        viewModel: SubscriptionViewModel(
                            billingManager: container.billingManager,
                            billingService: container.makeBillingService(),
                            authManager: container.authManager
                        )
                    )
                )
            }
            return view
        }

        #if os(macOS)
        return sheet(item: coverDestinations) {
            coverContent($0)
                .frame(minWidth: 600, minHeight: 450)
        }
        #else
        return fullScreenCover(item: coverDestinations, content: coverContent)
        #endif
    }
}
