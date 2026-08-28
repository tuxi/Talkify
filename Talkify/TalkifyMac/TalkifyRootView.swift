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
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppContainer.self) private var container
    @AppStorage("provider.onboarding.completed.v1")
    private var hasCompletedProviderOnboarding = false

    var body: some View {
        WorkspaceView(dependencies: container.makeAgentDependencies())
            .background(Color(nsColor: colorScheme == .dark
                              ? NSColor.windowBackgroundColor
                              : NSColor(
                                calibratedRed: 249.0 / 255.0,
                                green: 249.0 / 255.0,
                                blue: 249.0 / 255.0,
                                alpha: 1
                              )))
            .id(container.runtimeServers.activeIdentityRevision)
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
                    && container.runtimeServers.activeConnection?.kind == .embedded
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
