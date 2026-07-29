//
//  TalkifyRootView.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/6/24.
//

#if os(macOS)

import SwiftUI
import AgentKit
import CoreKit
import FeatureAuth

struct TalkifyRootView: View {
    
    @Environment(AppContainer.self) private var container
    @AppStorage("provider.onboarding.completed.v1")
    private var hasCompletedProviderOnboarding = false

    var body: some View {
        WorkspaceView(dependencies: container.makeAgentDependencies())
            .sheet(isPresented: providerOnboardingBinding) {
                ProviderOnboardingView(
                    hasCompletedOnboarding: $hasCompletedProviderOnboarding
                )
            }
            .sheet(isPresented: loginBinding) {
            AuthView(
                viewModel: container.makeAuthViewModel(),
                showsAppleSignIn: AppDistribution.current.supportsNativeAppleSignIn
            )
        }
    }

    private var providerOnboardingBinding: Binding<Bool> {
        Binding(
            get: {
                !hasCompletedProviderOnboarding
                    && !container.providerConnections.hasAvailableModels
                    && !container.authManager.showLoginSheet
            },
            set: { presented in
                if !presented { hasCompletedProviderOnboarding = true }
            }
        )
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { container.authManager.showLoginSheet },
            set: { container.authManager.showLoginSheet = $0 }
        )
    }
}

#Preview {
    TalkifyRootView()
}

#endif
