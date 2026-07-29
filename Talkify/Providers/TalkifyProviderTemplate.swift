import Foundation
import AgentKit

struct TalkifyProviderTemplate: Identifiable, Hashable {
    enum Kind: Hashable {
        case gateway
        case apiKey
        case local
        case custom
    }

    let id: String
    let displayName: String
    let summary: String
    let systemImage: String
    let kind: Kind
    let baseURL: URL?
    let models: [ProviderModel]

    static let builtIn: [TalkifyProviderTemplate] = [
        .init(
            id: ProviderConnection.talkifyGatewayID,
            displayName: "Talkify Gateway",
            summary: "使用 Talkify 账户、订阅模型和云端能力",
            systemImage: "person.crop.circle.badge.checkmark",
            kind: .gateway,
            baseURL: nil,
            models: []
        ),
        .init(
            id: "deepseek",
            displayName: "DeepSeek",
            summary: "使用 DeepSeek API 密钥连接",
            systemImage: "brain.head.profile",
            kind: .apiKey,
            baseURL: URL(string: "https://api.deepseek.com")!,
            models: [
                ProviderModel(
                    id: "deepseek-v4-flash",
                    displayName: "DeepSeek V4 Flash",
                    contextWindow: 1_000_000,
                    supportsTools: true,
                    supportsReasoning: true
                ),
                ProviderModel(
                    id: "deepseek-v4-pro",
                    displayName: "DeepSeek V4 Pro",
                    contextWindow: 1_000_000,
                    supportsTools: true,
                    supportsReasoning: true
                ),
            ]
        ),
        .init(
            id: "qwen",
            displayName: "Alibaba Qwen",
            summary: "使用阿里云百炼 OpenAI 兼容接口",
            systemImage: "cloud",
            kind: .apiKey,
            baseURL: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            models: [
                ProviderModel(id: "qwen3-coder-plus", displayName: "Qwen3 Coder Plus"),
                ProviderModel(id: "qwen-plus", displayName: "Qwen Plus"),
            ]
        ),
        .init(
            id: "zhipu",
            displayName: "Zhipu GLM",
            summary: "使用智谱 OpenAI 兼容接口",
            systemImage: "sparkles",
            kind: .apiKey,
            baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
            models: [
                ProviderModel(id: "glm-5", displayName: "GLM-5", supportsReasoning: true),
                ProviderModel(id: "glm-4.5", displayName: "GLM-4.5", supportsReasoning: true),
            ]
        ),
        .init(
            id: "openrouter",
            displayName: "OpenRouter",
            summary: "通过一个 API 密钥使用多个模型",
            systemImage: "point.3.connected.trianglepath.dotted",
            kind: .apiKey,
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            models: [
                ProviderModel(id: "openrouter/auto", displayName: "OpenRouter Auto"),
            ]
        ),
        .init(
            id: "ollama",
            displayName: "Ollama",
            summary: "连接本机或局域网中的 Ollama",
            systemImage: "desktopcomputer",
            kind: .local,
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            models: [
                ProviderModel(id: "qwen3", displayName: "Qwen3"),
            ]
        ),
        .init(
            id: "openai-compatible",
            displayName: "自定义提供商",
            summary: "配置任意 OpenAI-compatible 或 Ollama 连接",
            systemImage: "slider.horizontal.3",
            kind: .custom,
            baseURL: nil,
            models: []
        ),
    ]

    func suggestedConnectionID(existing: Set<String>) -> String {
        guard existing.contains(id) else { return id }
        var suffix = 2
        while existing.contains("\(id)-\(suffix)") {
            suffix += 1
        }
        return "\(id)-\(suffix)"
    }
}
