import SwiftUI
import CoreKit

struct ProviderOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    @Binding var hasCompletedOnboarding: Bool
    @State private var editor: ProviderEditorRequest?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("连接模型服务")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Talkify 无需登录即可使用工作区。连接任意服务商后，即可在会话中发送消息。")
                        .foregroundStyle(.secondary)
                }

                onboardingButton(
                    title: "连接 Talkify Gateway",
                    subtitle: "使用 Talkify 账户、订阅模型和云端能力",
                    symbol: "person.crop.circle.badge.checkmark"
                ) {
                    finish()
                    Task { @MainActor in
                        await Task.yield()
                        container.requestGatewayConnection()
                    }
                }

                onboardingButton(
                    title: "使用 API 密钥",
                    subtitle: "连接 DeepSeek、Qwen、GLM、OpenRouter 或自定义服务",
                    symbol: "key"
                ) {
                    let templates = container.providerConnections.talkifyTemplates
                    if let template = templates.first(where: {
                        $0.id == "deepseek"
                    }) {
                        editor = .create(template)
                    }
                }

                onboardingButton(
                    title: "连接本地模型",
                    subtitle: "连接本机或局域网中的 Ollama",
                    symbol: "desktopcomputer"
                ) {
                    let templates = container.providerConnections.talkifyTemplates
                    if let template = templates.first(where: {
                        $0.id == "ollama"
                    }) {
                        editor = .create(template)
                    }
                }

                Button("稍后配置") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                Spacer()
            }
            .padding(30)
            .frame(maxWidth: 620, alignment: .leading)
            .navigationTitle("开始使用 Talkify")
            .onChange(of: container.providerConnections.hasAvailableModels) { _, available in
                if available { finish() }
            }
            .sheet(item: $editor) { request in
                ProviderEditorView(request: request, store: container.providerConnections)
                    #if os(macOS)
                    .frame(minWidth: 680, minHeight: 680)
                    #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 560)
        #endif
    }

    private func onboardingButton(
        title: String,
        subtitle: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.10))
            }
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        hasCompletedOnboarding = true
        dismiss()
    }
}
