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
    let api: String?
    let env: String?
    let models: [ProviderModel]

    /// Build the template list from runtime-fetched templates plus a local
    /// "custom" entry. The runtime's `builtinConnections` is the single source
    /// of truth for known services; the custom template covers arbitrary
    /// OpenAI-compatible / Ollama connections that have no server-side builtin.
    static func all(from runtimeTemplates: [RuntimeProviderTemplate]) -> [TalkifyProviderTemplate] {
        var out = runtimeTemplates.map { template in
            let kind = Kind.fromRuntime(template.kind)
            return TalkifyProviderTemplate(
                id: template.id,
                displayName: template.displayName ?? template.id,
                summary: template.summary ?? "",
                systemImage: systemImageFor(kind: kind, id: template.id),
                kind: kind,
                baseURL: template.baseURL.flatMap(URL.init(string:)),
                api: template.api,
                env: template.env,
                models: (template.models ?? []).map { m in
                    ProviderModel(
                        id: m.id,
                        runtimeAlias: m.runtimeAlias,
                        contextWindow: m.contextWindow,
                        temperature: m.temperature,
                        supportsTools: m.supportsTools ?? true,
                        supportsReasoning: m.supportsReasoning ?? false,
                        inputModalities: Set((m.inputModalities ?? []).compactMap {
                            ProviderInputModality(rawValue: $0)
                        }),
                        inputPricePerMillion: m.inputPricePerMillion,
                        outputPricePerMillion: m.outputPricePerMillion,
                        webSearch: m.webSearch ?? false,
                        supportedReasoningEfforts: m.supportedReasoningEfforts,
                        canDisableReasoning: m.canDisableReasoning ?? true,
                        reasoningEffort: m.reasoningEffort,
                    )
                }
            )
        }
        out.append(customTemplate)
        return out
    }

    /// Local-only "custom" template for arbitrary OpenAI-compatible / Ollama connections.
    static let customTemplate = TalkifyProviderTemplate(
        id: "openai-compatible",
        displayName: "自定义提供商",
        summary: "配置任意 OpenAI-compatible 或 Ollama 连接",
        systemImage: "slider.horizontal.3",
        kind: .custom,
        baseURL: nil,
        api: nil,
        env: nil,
        models: []
    )

    func suggestedConnectionID(existing: Set<String>) -> String {
        guard existing.contains(id) else { return id }
        var suffix = 2
        while existing.contains("\(id)-\(suffix)") {
            suffix += 1
        }
        return "\(id)-\(suffix)"
    }

    private static func systemImageFor(kind: Kind, id: String) -> String {
        switch kind {
        case .gateway: return "person.crop.circle.badge.checkmark"
        case .local:  return "desktopcomputer"
        case .apiKey:
            switch id {
            case "deepseek":   return "brain.head.profile"
            case "qwen":       return "cloud"
            case "glm":        return "sparkles"
            case "openrouter": return "point.3.connected.trianglepath.dotted"
            default:           return "key"
            }
        case .custom: return "slider.horizontal.3"
        }
    }
}

private extension TalkifyProviderTemplate.Kind {
    static func fromRuntime(_ kind: String?) -> TalkifyProviderTemplate.Kind {
        switch kind {
        case "gateway": return .gateway
        case "local":   return .local
        case "api_key": return .apiKey
        default:        return .custom
        }
    }
}
