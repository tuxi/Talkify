//
//  CodeAgentApp.swift
//  CodeAgent
//
//  Created by xiaoyuan on 2026/6/24.
//

import SwiftUI
import AgentKit
import CoreKit
import FeatureAuth

let keyChinGroupID = "NKW67GFDHM.com.objc.chat.shared"

@main
struct TalkifyApp: App {

    private var container: AppContainer
    private let environmentManager: EnvironmentManager
    private let deviceManager = DeviceManager(keychainGroupId: keyChinGroupID)
    
    init() {
        
        let environmentManager = EnvironmentManager()
        #if DEBUG
        environmentManager.saveCurrentEnvironment(.local)
        #else
        environmentManager.saveCurrentEnvironment(.prod)
        #endif
        self.environmentManager = environmentManager
        
        let manager = AuthManager(
            environment: environmentManager.currentEnvironmentSnapshot,
            refreshTokenHandler: { token in
                return try await ApiProvider.defaultApiProvider(environmentConfig: environmentManager.currentConfig)
                    .request(endpoint: AuthApi.refreshToken(token: token.refreshToken))
            },
            anonymousRegisterHandler: { [deviceManager, environmentManager] in
                let apiProvider = await ApiProvider.defaultApiProvider(environmentConfig: environmentManager.currentConfig)
                let authService = AuthService(api: apiProvider)
                let deviceId = try await deviceManager.getDeviceId()
                return try await authService.anonymousRegister(deviceId: deviceId)
            }
        )
        self.container = AppContainer(authManager: manager, environmentManager: environmentManager, deviceManager: deviceManager)
    }

    var body: some Scene {
        WindowGroup {
            CodeAgentRootView()
                .environment(container)
                .environment(container.agentManager)
                .environment(container.modelSettings)
                .environment(container)
                .environment(container.authManager)
                .environment(container.userManager)
//                .environment(container.billingManager)
                .environment(environmentManager)
                .environment(deviceManager)
                .onChange(of: container.authManager.isLoggedIn, { oldValue, newValue in
//                    toggleConnect()
                })
                .onAppear {
                    Task { @MainActor in
                        await container.authManager.ensureInitialIdentity()
//                        toggleConnect()
                        if container.authManager.isRegistered {
                            await container.userManager.refreshProfileIfNeeded(maxAge: 0)
//                            await container.billingManager.refreshAllIfNeeded(maxAge: 0)
                        }
                    }
                }
        }
    }
}

extension ApiProvider {
    @MainActor static func defaultApiProvider(environmentConfig: AppEnvironmentConfig = EnvironmentRegistry.live.config(for: .prod)) -> ApiProvider {
        let baseHeaders = BaseHeader(deviceInfo: DeviceManager.deviceInfo).toDictionary() ?? [:]
        let refreshConfig = NetworkConfig(
            baseURL: environmentConfig.apiBaseURL,
            commonHeaders: baseHeaders
        )
        let apiProvider = ApiProvider(config: refreshConfig)
        return apiProvider
    }
}

extension DeviceManager {
static var deviceInfo: DeviceInfo {
        let devcice = DeviceManager(keychainGroupId: keyChinGroupID)
        return try! devcice.getDeviceInfo()
    }
}
