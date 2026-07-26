//
//  AppGlobalModalRouter.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/19.
//

import SwiftUI
import CoreKit
import FeatureAuth

@MainActor
extension View {
    func withAppGlobalModalCoordinator(
        coordinator: AppModalCoordinator,
        container: AppContainer
    ) -> some View {
        Group {
#if os(macOS)
sheet(item: Binding(
    get: { coordinator.presentedCover },
    set: { coordinator.presentedCover = $0 }
)) { destination in
    globalCoverContent(destination, container: container)
        .frame(minWidth: 600, minHeight: 450)
}
.sheet(item: Binding(
    get: { coordinator.browserURL },
    set: { coordinator.browserURL = $0 }
)) { wrapper in
    NavigationStack {
        BrowserView(url: wrapper.url)
    }
}
#else
            if DeviceInfo.isPadLayout {
                sheet(item: Binding(
                    get: { coordinator.presentedCover },
                    set: { coordinator.presentedCover = $0 }
                )) { destination in
                    globalCoverContent(destination, container: container)
                        .frame(minWidth: 600, minHeight: 800)
                }
                .sheet(item: Binding(
                    get: { coordinator.browserURL },
                    set: { coordinator.browserURL = $0 }
                )) { wrapper in
                    NavigationStack {
                        BrowserView(url: wrapper.url)
                    }
                }
            } else {
                fullScreenCover(item: Binding(
                    get: { coordinator.presentedCover },
                    set: { coordinator.presentedCover = $0 }
                )) { destination in
                    globalCoverContent(destination, container: container)
                }
                .sheet(item: Binding(
                    get: { coordinator.browserURL },
                    set: { coordinator.browserURL = $0 }
                )) { wrapper in
                    NavigationStack {
                        BrowserView(url: wrapper.url)
                    }
                }
            }
#endif
        }
    }

    @ViewBuilder
    private func globalCoverContent(
        _ destination: AppGlobalCoverDestination,
        container: AppContainer
    ) -> some View {
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
        case .auth:
            AuthView(viewModel: container.makeAuthViewModel())
        }
    }
}
