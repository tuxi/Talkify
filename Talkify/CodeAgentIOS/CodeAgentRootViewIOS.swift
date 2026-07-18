//
//  CodeAgentRootView.swift
//  CodeAgent
//
//  Created by xiaoyuan on 2026/6/24.
//

#if os(iOS)

import SwiftUI
import AgentKit
import CoreKit
import FeatureAuth

struct CodeAgentRootView: View {
    @Environment(AppContainer.self) private var container
    
    init() {

    }

    var body: some View {
        if container.authManager.isLoggedIn {
            WorkspaceView(dependencies: container.makeAgentDependencies())
        } else {
            AuthView(viewModel: container.makeAuthViewModel())
        }
    }
}

#endif
