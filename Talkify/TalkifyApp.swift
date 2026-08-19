//
//  TalkifyApp.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/6/24.
//

import SwiftUI
import AgentKit
import CoreKit
import FeatureAuth
import FileViewerKit
#if os(macOS)
import AppKit
#endif

#if os(macOS) && TALKIFY_MAC_DIRECT
// Direct distribution deliberately avoids restricted entitlements so that
// Developer ID signing does not require a provisioning profile.
let keychainGroupID: String? = nil
#else
let keychainGroupID: String? = "NKW67GFDHM.com.objc.chat.shared"
#endif

#if os(macOS)
private final class TalkifyApplicationDelegate: NSObject, NSApplicationDelegate {
    var sharingController: RuntimeSharingController?

    func applicationWillTerminate(_ notification: Notification) {
        sharingController?.stopSharing()
        #if os(macOS)
        CodeAgentDaemon.shared.stop()
        #else
        AgentRuntime.shared.stop()
        #endif
    }
}
#endif

@main
struct TalkifyApp: App {

    private var container: AppContainer
    private let environmentManager: EnvironmentManager
    private let deviceManager = DeviceManager(keychainGroupId: keychainGroupID)
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TalkifyApplicationDelegate.self)
    private var applicationDelegate
    #endif

    @State private var pendingWorkspaceItem: WorkspaceItem?

    init() {
        #if os(macOS)
        // 单实例保护：同一时刻只允许一个 Talkify 实例运行。
        // 第二个实例会激活已运行的实例并立即退出，避免两个实例各自启动
        // 同名的 codeagentd 子进程并互相 pkill -9 杀死对方——SIGKILL 会触发
        // 崩溃自动重启循环，且可能打断共享 sessions.db 的写入（曾导致会话库
        // 被隔离重建）。守卫放在最前面，确保在任何 daemon 启动之前生效。
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            exit(0)
        }
        #endif

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
        #if os(macOS)
        applicationDelegate.sharingController = container.sharingController
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TalkifyRootView()
                .environment(container)
                .environment(container.agentManager)
                .environment(container.modelSettings)
                .environment(container.authManager)
                .environment(container.userManager)
                .environment(container.billingManager)
                .environment(environmentManager)
                .environment(deviceManager)
                .onChange(of: container.authManager.isRegistered, { _, _ in
                    container.synchronizeGatewayConnectionWithIdentity()
                })
                .onChange(of: container.authManager.token?.userId) { _, _ in
                    Task { await container.userAssetPreviewResolver.clearCache() }
                }
                .onAppear {
                    Task { @MainActor in
                        if container.authManager.isRegistered {
                            await container.refreshGatewayConnection()
                        }
                    }
                }
                .environment(\.openURL, OpenURLAction(handler: { url in
                    return handleDeepLink(url)
                }))
        }
        
    }
    
    private func handleDeepLink(_ url: URL) -> OpenURLAction.Result {
        let url = resolveAppURL(url)
        // talkify://workspace?path=/Users/xxx/my-project
        if url.scheme == "talkifyapp" || url.scheme == "talkify" || url.scheme == "codeagent" {
            // Share Extension 只负责唤醒主 App；ChatRootViewController 会从
            // App Group Inbox 读取并展示工作区确认页。
            if url.host == "shared-import" {
                return .handled
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let pathItem = components.queryItems?.first(where: {
                   $0.name == "path"
               }),
               let path = pathItem.value,
               let path = path.removingPercentEncoding {
                #if os(macOS)
                openFolderInFinder(path: path)
                #endif
                container.pendingDeepLinkWorkspacePath = path.resolvingCurrentSandboxPath
            }
            return .handled // 阻止系统弹窗或外部浏览器打开
        }
        return .systemAction
    }
    
    private func resolveAppURL(_ url: URL) -> URL {
        guard url.scheme == "talkify" else { return url }

        switch url.host {
        case "user-agreement":
            return AgreementURLs.terms
        case "privacy-policy":
            return AgreementURLs.privacy
        case "ai-data-processing":
            return AgreementURLs.AIData
        default:
            return url
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
        let devcice = DeviceManager(keychainGroupId: keychainGroupID)
        return try! devcice.getDeviceInfo()
    }
}
