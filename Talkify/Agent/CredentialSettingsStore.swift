//
//  CredentialSettingsStore.swift
//  AgentKit
//
//  UI 层 credential 配置 store（@MainActor @Observable）。
//

import SwiftUI
import AgentKit

// MARK: - Provider Mode

public enum ProviderMode: String, CaseIterable, Sendable {
    case gateway
    case byok
}

// MARK: - BYOK Provider Config

public struct BYOKProviderConfig: Identifiable, Sendable {
    public let namespace: String
    public let name: String
    public let displayName: String
    public var isConfigured: Bool

    public var id: String { "\(namespace)/\(name)" }

    public init(namespace: String, name: String, displayName: String, isConfigured: Bool = false) {
        self.namespace = namespace
        self.name = name
        self.displayName = displayName
        self.isConfigured = isConfigured
    }

    var target: CredentialTarget {
        CredentialTarget(namespace: namespace, name: name)
    }
}

// MARK: - CredentialSettingsStore

@MainActor
@Observable
public final class CredentialSettingsStore {

    public var selectedProvider: ProviderMode = .gateway
    public var byokProviders: [BYOKProviderConfig]
    public var selectedBYOKName: String?
    public var byokKey: String = ""
    /// BYOK 模式的默认模型别名（config.yaml `models:` 别名，Runtime 启动时读取）。
    /// Gateway 模式的模型选择在 DraftComposerPanel 中按对话管理，与此无关。
    public var model: String

    private let store: any CredentialStore

    public init(store: any CredentialStore) {
        self.store = store
        self.model = AgentSettings.model
        self.byokProviders = [
            BYOKProviderConfig(namespace: "llm", name: "deepseek", displayName: "DeepSeek"),
            BYOKProviderConfig(namespace: "llm", name: "openai", displayName: "OpenAI"),
            BYOKProviderConfig(namespace: "llm", name: "anthropic", displayName: "Anthropic"),
            BYOKProviderConfig(namespace: "llm", name: "ollama", displayName: "Ollama (Local)"),
        ]
    }

    /// 刷新 BYOK 配置状态。
    public func refresh() async {
        for i in byokProviders.indices {
            if let _ = try? await store.resolve(byokProviders[i].target) {
                byokProviders[i].isConfigured = true
            }
        }
    }

    /// 保存 BYOK key 到 Keychain。
    public func saveBYOKKey() async throws {
        guard let name = selectedBYOKName,
              !byokKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let target = CredentialTarget.llm(name)
        let cred = Credential(kind: .bearer, secret: byokKey.trimmingCharacters(in: .whitespacesAndNewlines))
        try await store.set(cred, for: target)
        byokKey = ""

        // 刷新配置状态
        if let idx = byokProviders.firstIndex(where: { $0.name == name }) {
            byokProviders[idx].isConfigured = true
        }

        await reconfigureRuntime()
    }

    /// 删除 BYOK key。
    public func removeBYOKKey(_ name: String) async throws {
        try await store.remove(.llm(name))
        if let idx = byokProviders.firstIndex(where: { $0.name == name }) {
            byokProviders[idx].isConfigured = false
        }

        await reconfigureRuntime()
    }

    /// credential 变更后热更新内嵌 Runtime（credential-injection-v1 §4）。
    /// macOS 连接远端 server，credential 由启动参数/请求头注入，无需此步。
    private func reconfigureRuntime() async {
        #if os(iOS)
        try? await AgentRuntime.shared.reconfigure(with: store)
        #endif
    }

    /// 保存模型选择。
    public func saveModel() {
        UserDefaults.standard.set(model, forKey: AgentSettings.modelDefaultsKey)
    }
}
