import SwiftUI
import AgentKit
import CoreKit
import DesignKit

struct ProviderSettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var editor: ProviderEditorRequest?
    @State private var pendingRemoval: ProviderConnection?
    @State private var errorMessage: String?

    private var store: ProviderConnectionStore { container.providerConnections }
    private var isExternalServerActive: Bool {
        container.runtimeServers.activeConnection?.kind == .remote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if isExternalServerActive {
                externalServerNotice
            } else {
                if store.isDaemonOffline {
                    daemonOfflineNotice
                } else {
                    runtimeConfigurationStatus

                    if !store.connections.isEmpty {
                        providerSection(title: "已连接的提供商") {
                            ForEach(store.connections) { connection in
                                connectedRow(connection)
                                if connection.id != store.connections.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }

                    providerSection(title: "可连接的提供商") {
                        ForEach(store.talkifyTemplates) { template in
                            availableRow(template)
                            if template.id != store.talkifyTemplates.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .task {
            await store.refreshCacheFromRuntime()
        }
        .frame(maxWidth: 780, alignment: .leading)
        .sheet(item: $editor) { request in
            ProviderEditorView(request: request, store: store)
                #if os(macOS)
                .frame(minWidth: 680, minHeight: 680)
                #endif
        }
        .alert(
            "断开提供商？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { connection in
            Button("取消", role: .cancel) {}
            Button("断开连接", role: .destructive) {
                Task { await remove(connection) }
            }
        } message: { connection in
            Text("历史会话会保留，但使用“\(connection.displayName)”模型的会话在重新选择模型前不能发送消息。")
        }
        .alert("错误", isPresented: .init(get: {
            (errorMessage ?? "").isEmpty == false
        }, set: { _ in
            errorMessage = nil
        })) {
            Button("OK") {
           
            }
        } message: {
            if let errorMessage, errorMessage.contains("provider is referenced by default_model") {
                Text("该提供商的模型是当前默认模型，请先在设置中切换默认模型，或手动编辑 settings.json 后再断开")
                    .font(.caption2)
            } else {
                Text(errorMessage ?? "未知信息")
                    .font(.caption2)
            }
        }
        .onChange(of: store.lastSecretsPushError) { oldValue, newValue in
            if let newValue, !newValue.isEmpty {
                errorMessage = "模型凭据同步失败：\(newValue)"
            }
        }
        .onChange(of: store.sharedSecretsFileError) { oldValue, newValue in
            if let newValue, !newValue.isEmpty {
                errorMessage = "共享凭据文件写入失败：\(newValue)"
            }
        }
    }

    @ViewBuilder
    private var externalServerNotice: some View {
        let name = container.runtimeServers.activeConnection?.displayName ?? "未知服务器"
        ContentUnavailableView {
            Label("提供商由外部服务器管理", systemImage: "server.rack")
        } description: {
            Text(" 当前连接的是[\(name)]。 Talkify 只读取该 CodeAgent Server 发布的模型，不会查看或修改它的 Provider 与 API Key。")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    /// Stage ③: degraded state when the desktop codeagentd daemon is not
    /// reachable for /v1/providers management.
    private var daemonOfflineNotice: some View {
        ContentUnavailableView {
            Label("Runtime 不可达", systemImage: "server.rack")
        } description: {
            Text("本地 CodeAgent 服务未运行，提供商配置暂不可用。请稍后重试，或在 Runtime 服务器设置中重新连接。")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    @ViewBuilder
    private var runtimeConfigurationStatus: some View {
        if store.isApplyingRuntimeConfiguration {
            HStack(alignment: .top, spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在应用配置")
                        .font(.system(size: 14, weight: .medium))
                    Text(
                        store.runtimeConfigurationError
                            ?? "新模型会在本地 Runtime 配置生效后出现在会话中。"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        store.runtimeConfigurationError == nil
                            ? Color.secondary
                            : Color.red
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func providerSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
        }
    }

    private func connectedRow(_ connection: ProviderConnection) -> some View {
        HStack(spacing: 14) {
            providerIcon(connection.id)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(connection.displayName)
                        .font(.system(size: 16, weight: .medium))
                    credentialBadge(connection)
                }
                Text("\(connection.models.count) 个模型 · \(connection.baseURL.host ?? connection.baseURL.absoluteString)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if store.pendingRestartConnectionIDs.contains(connection.id) {
                    Text("已保存，重启后生效")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if connection.isTalkifyGateway {
                Text("已连接")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { connection.isEnabled },
                        set: { store.setEnabled($0, connectionID: connection.id) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Menu {
                if !connection.isTalkifyGateway {
                    Button("编辑") {
                        editor = .edit(connection)
                    }
                }
                Button("断开连接", role: .destructive) {
                    pendingRemoval = connection
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if !connection.isTalkifyGateway {
                editor = .edit(connection)
            }
        }
    }

    private func availableRow(_ template: TalkifyProviderTemplate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: template.systemImage)
                .font(.system(size: 18))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(template.displayName)
                    .font(.system(size: 16, weight: .medium))
                Text(template.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if template.kind == .gateway {
                    container.requestGatewayConnection()
                } else {
                    editor = .create(template)
                }
            } label: {
                Label(
                    store.connections.contains(where: { $0.id == template.id })
                        ? "再连接"
                        : "连接",
                    systemImage: "plus"
                )
            }
            .buttonStyle(.bordered)
            .disabled(template.kind == .gateway && container.authManager.isRegistered)
        }
        .padding(.vertical, 16)
    }

    private func providerIcon(_ providerID: String) -> some View {
        let symbol = store.talkifyTemplates
            .first(where: { $0.id == providerID })?.systemImage ?? "server.rack"
        return Image(systemName: symbol)
            .font(.system(size: 18))
            .frame(width: 28)
    }

    private func credentialBadge(_ connection: ProviderConnection) -> some View {
        let label: String
        switch connection.authentication {
        case .gatewayAccount: label = "Gateway 账户"
        case .apiKey: label = "API 密钥"
        case .none: label = "本地"
        }
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    private func remove(_ connection: ProviderConnection) async {
        pendingRemoval = nil
        do {
            if connection.isTalkifyGateway {
                await container.disconnectGateway()
            } else {
                try await store.remove(connectionID: connection.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ProviderEditorRequest: Identifiable {
    case create(TalkifyProviderTemplate)
    case edit(ProviderConnection)

    var id: String {
        switch self {
        case .create(let template): "create-\(template.id)"
        case .edit(let connection): "edit-\(connection.id)"
        }
    }
}

private struct ProviderModelDraft: Identifiable {
    let id = UUID()
    var wireModelID: String = ""
    var runtimeAlias: String = ""
    var transport: ProviderTransport? = nil
    var displayName: String = ""
    var contextWindow: String = ""
    var temperature: String = ""
    var supportsTools = true
    var supportsReasoning = false
    var inputModalities: Set<ProviderInputModality> = [.text]
    var inputPricePerM: String = ""
    var outputPricePerM: String = ""
    var cacheInputPricePerM: String = ""
    var webSearch = false
    var supportedReasoningEfforts: [ModelReasoningEffort]  = []
    var canDisableReasoning: Bool = true
    var reasoningEffort: ModelReasoningEffort?

    init(model: ProviderModel? = nil) {
        wireModelID = model?.id ?? ""
        runtimeAlias = model?.runtimeAlias ?? ""
        transport = ProviderTransport(api: model?.api)
        displayName = model?.displayName ?? ""
        contextWindow = model?.contextWindow.map(String.init) ?? ""
        temperature = model?.temperature.map { String(format: "%.2f", $0) } ?? ""
        supportsTools = model?.supportsTools ?? true
        supportsReasoning = model?.supportsReasoning ?? false
        inputModalities = model?.inputModalities ?? [.text]
        inputPricePerM = model?.inputPricePerMillion.map { String(format: "%.2f", $0) } ?? ""
        outputPricePerM = model?.outputPricePerMillion.map { String(format: "%.2f", $0) } ?? ""
        cacheInputPricePerM = model?.cacheInputPricePerMillion.map { String(format: "%.2f", $0) } ?? ""
        webSearch = model?.webSearch ?? false
        supportedReasoningEfforts = model?.supportedReasoningEfforts ?? []
        canDisableReasoning = model?.canDisableReasoning ?? true
        reasoningEffort = model?.reasoningEffort ?? model?.supportedReasoningEfforts?.first
    }

    var providerModel: ProviderModel {
        ProviderModel(
            id: wireModelID.trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeAlias: runtimeAlias.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            api: transport?.api,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            contextWindow: Int(contextWindow),
            temperature: Double(temperature),
            supportsTools: supportsTools,
            supportsReasoning: supportsReasoning,
            inputModalities: inputModalities,
            inputPricePerMillion: Double(inputPricePerM),
            outputPricePerMillion: Double(outputPricePerM),
            cacheInputPricePerMillion: Double(cacheInputPricePerM),
            webSearch: webSearch,
            supportedReasoningEfforts: supportedReasoningEfforts,
            canDisableReasoning: canDisableReasoning,
            reasoningEffort: reasoningEffort
        )
    }
}

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let request: ProviderEditorRequest
    let store: ProviderConnectionStore
    var isCustomConnection: Bool {
        switch request {
        case .create(let talkifyProviderTemplate):
            return talkifyProviderTemplate.kind == .custom || talkifyProviderTemplate.kind == .local
        case .edit(let providerConnection):
            let index = store.providerTemplates.firstIndex {
                $0.id == providerConnection.id
            }
            return index == nil
        }
    }

    @State private var connectionID: String
    @State private var displayName: String
    @State private var baseURL: String
    @State private var transport: ProviderTransport
    @State private var authentication: ProviderAuthentication
    @State private var apiKey = ""
    @State private var models: [ProviderModelDraft]
    @State private var allowsInsecurePrivateNetworkHTTP: Bool
    @State private var showsAdvancedSettings = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isNew: Bool {
        if case .create = request { true } else { false }
    }

    private var usesSimplifiedAPIKeyForm: Bool {
        guard case .create(let template) = request else { return false }
        return template.kind == .apiKey
    }

    init(request: ProviderEditorRequest, store: ProviderConnectionStore) {
        self.request = request
        self.store = store

        switch request {
        case .create(let template):
            let id = template.suggestedConnectionID(
                existing: Set(store.connections.map(\.id))
            )
            _connectionID = State(initialValue: id)
            _displayName = State(initialValue: template.displayName)
            _baseURL = State(initialValue: template.baseURL?.absoluteString ?? "")
            _transport = State(initialValue: template.kind == .local ? .ollama : .openAIChatCompletions)
            _authentication = State(initialValue: template.kind == .local ? .none : .apiKey)
            _models = State(initialValue: template.models.map {
                ProviderModelDraft(model: $0)
            })
            _allowsInsecurePrivateNetworkHTTP = State(initialValue: false)
        case .edit(let connection):
            _connectionID = State(initialValue: connection.id)
            _displayName = State(initialValue: connection.displayName)
            _baseURL = State(initialValue: connection.baseURL.absoluteString)
            _transport = State(initialValue: connection.transport)
            _authentication = State(initialValue: connection.authentication)
            _models = State(initialValue: connection.models.map { ProviderModelDraft(model: $0) })
            _allowsInsecurePrivateNetworkHTTP = State(
                initialValue: connection.allowsInsecurePrivateNetworkHTTP
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if usesSimplifiedAPIKeyForm {
                        SecureField("API 密钥", text: $apiKey)
                        DisclosureGroup(
                            "高级设置",
                            isExpanded: $showsAdvancedSettings
                        ) {
                            connectionFields(includeCredential: false)
                        }
                    } else {
                        connectionFields(includeCredential: true)
                    }
                } header: {
                    Text("连接")
                }

                if isCustomConnection {
                    Section {
                        ForEach($models) { $model in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    TextField("Model ID", text: $model.wireModelID)
                                    Button(role: .destructive) {
                                        models.removeAll { $0.id == model.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                TextField("Runtime Alias（可选）", text: $model.runtimeAlias)
                                TextField("显示名称（可选）", text: $model.displayName)
                                TextField("Context Window（可选）", text: $model.contextWindow)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                Toggle("Tool Calling", isOn: $model.supportsTools)
                                Toggle("Reasoning", isOn: $model.supportsReasoning)
                                if model.supportsReasoning {
                                    VStack {
                                        Toggle("Allow disabling reasoning", isOn: $model.canDisableReasoning)
                                        HStack {
                                            Text("Default reasoning effort")
                                            Spacer()
                                            Menu {
                                                ForEach(ModelReasoningEffort.allCases, id: \.name) { item in
                                                    Button {
                                                        model.reasoningEffort = item
                                                    } label: {
                                                        Text(item.name)
                                                    }
                                                }
                                            } label: {
                                                Text(model.reasoningEffort?.name ?? "auto")
                                            }
                                            .menuStyle(.borderlessButton)
                                            .fixedSize()
                                        }
                                        
                                        ReasoningEffortView(selected: Binding(get: {
                                            return Set(model.supportedReasoningEfforts)
                                        }, set: { items in
                                            model.supportedReasoningEfforts = Array(items)
                                        }))
                                    }
                                    .padding(.leading, 12)
                                }
                                Toggle("Web Search", isOn: $model.webSearch)
                                ModelCapSelectView(selectedCaps: $model.inputModalities)
                                DisclosureGroup("高级") {
//                                    TextField("协议（可选）", text: $model.transport)
                                    Picker("协议", selection: $model.transport) {
                                        Text("OpenAI-Chat-Completions").tag(ProviderTransport.openAIChatCompletions)
                                        Text("OpenAI-Responses").tag(ProviderTransport.openAIResponses)
                                        Text("Ollama").tag(ProviderTransport.ollama)
                                    }
                                    TextField("Temperature（可选）", text: $model.temperature)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                    TextField("Input Price/M（可选）", text: $model.inputPricePerM)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                    TextField("Output Price/M（可选）", text: $model.outputPricePerM)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                    TextField("Cache Input Price/M（可选）", text: $model.cacheInputPricePerM)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        Button {
                            models.append(ProviderModelDraft())
                        } label: {
                            Label("添加模型", systemImage: "plus")
                        }
                    } header: {
                        Text("模型")
                    } footer: {
                        Text("至少配置一个模型后才能在会话中发送消息。")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "连接提供商" : "编辑提供商")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在保存…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private func connectionFields(includeCredential: Bool) -> some View {
        TextField("Connection ID", text: $connectionID)
            .disabled(!isNew)
            .allowsHitTesting(isCustomConnection)
        Text("只允许小写字母、数字、连字符和下划线；创建后不可修改。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .allowsHitTesting(isCustomConnection)
        TextField("显示名称", text: $displayName)
            .allowsHitTesting(isCustomConnection)
        TextField("Base URL", text: $baseURL)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .allowsHitTesting(isCustomConnection)
        Picker("协议", selection: $transport) {
            Text("OpenAI-Chat-Completions").tag(ProviderTransport.openAIChatCompletions)
            Text("OpenAI-Responses").tag(ProviderTransport.openAIResponses)
            Text("Ollama").tag(ProviderTransport.ollama)
        }
        .allowsHitTesting(isCustomConnection)
        Picker("认证", selection: $authentication) {
            Text("API 密钥").tag(ProviderAuthentication.apiKey)
            Text("无认证").tag(ProviderAuthentication.none)
        }
        .allowsHitTesting(isCustomConnection)
        if includeCredential && authentication == .apiKey {
            SecureField(isNew ? "API 密钥" : "API 密钥（留空则保持不变）", text: $apiKey)
        }
        if isPrivateNetworkHTTP {
            Toggle(
                "允许通过局域网 HTTP 发送数据",
                isOn: $allowsInsecurePrivateNetworkHTTP
            )
            Text("连接未加密。仅在你信任当前局域网和目标设备时启用。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var isPrivateNetworkHTTP: Bool {
        guard let url = URL(string: baseURL),
              url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased() else { return false }
        if ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(host) {
            return false
        }
        return true
    }

    private func save() async {
        errorMessage = nil
        let normalizedID = connectionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let validID = normalizedID.range(
            of: "^[a-z0-9][a-z0-9_-]*$",
            options: .regularExpression
        ) != nil
        guard validID else {
            errorMessage = "Connection ID 格式不正确。"
            return
        }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Base URL 格式不正确。"
            return
        }
        
        var providerModels = [ProviderModel]()
        if isCustomConnection {
            providerModels = models
                .map(\.providerModel)
                .filter { !$0.id.isEmpty }
            guard !providerModels.isEmpty else {
                errorMessage = "请至少添加一个模型。"
                return
            }
        }
        
        let connection = ProviderConnection(
            id: normalizedID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: transport,
            authentication: authentication,
            baseURL: url,
            models: providerModels,
            isEnabled: true,
            allowsInsecurePrivateNetworkHTTP: allowsInsecurePrivateNetworkHTTP
        )
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(connection, apiKey: apiKey, isNew: isNew)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ModelCatalogSettingsView: View {
    @Environment(AppContainer.self) private var container

    private var store: ProviderConnectionStore { container.providerConnections }
    private var isExternalServerActive: Bool {
        container.runtimeServers.activeConnection.map { $0.kind != .embedded } ?? false
    }
    private var activeDefaultModelID: String? {
        isExternalServerActive
            ? container.runtimeServers.activeContext?.defaultModelID
            : store.catalog.defaultModelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("模型")
                .font(.system(size: 30, weight: .semibold))

            if !isExternalServerActive && store.isApplyingRuntimeConfiguration {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在应用 Provider 配置，新模型暂不可选择。")
                        .foregroundStyle(.secondary)
                }
            }

            if container.modelSettings.unifiedModelGroups.isEmpty {
                ContentUnavailableView(
                    !isExternalServerActive && store.isApplyingRuntimeConfiguration
                        ? "模型配置中"
                        : "尚无可用模型",
                    systemImage: "sparkles",
                    description: Text(
                        !isExternalServerActive && store.isApplyingRuntimeConfiguration
                            ? "Runtime 准备完成后，模型会自动出现在会话中。"
                            : "当前 Runtime Server 没有发布可用模型。"
                    )
                )
            } else {
                ForEach(container.modelSettings.unifiedModelGroups, id: \.connectionID) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name)
                            .font(.system(size: 18, weight: .semibold))
                        VStack(spacing: 0) {
                            ForEach(group.models) { model in
                                modelRow(model)
                                if model.id != group.models.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
                    }
                }
            }
        }
        .frame(maxWidth: 780, alignment: .leading)
        .task {
            // The provider list and the published runtime model catalog are
            // separate snapshots. Refresh when this screen appears so models
            // added while it was off-screen become visible immediately.
            await container.refreshActiveRuntimeContext()
        }
    }

    private func modelRow(_ model: UnifiedModelDescriptor) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.system(size: 15, weight: .medium))
                HStack(spacing: 8) {
                    if let context = model.contextWindow {
                        Text("\(context.formatted()) 上下文")
                    }
                    if model.supportsTools { Text("工具") }
                    if model.supportsReasoning { Text("推理") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                guard !isExternalServerActive else { return }
                store.setDefaultModel(model.id)
            } label: {
                if activeDefaultModelID == model.id {
                    Label("默认", systemImage: "checkmark")
                } else if isExternalServerActive {
                    Text("服务器模型")
                } else {
                    Text("设为默认")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isExternalServerActive)
        }
        .padding(.vertical, 14)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct ModelCapSelectView: View {
    @Binding var selectedCaps: Set<ProviderInputModality>
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("模型支持能力")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(ProviderInputModality.allCases) { cap in
                    let isSelected = selectedCaps.contains(cap)
                    Text(cap.displayName)
                        .padding(.vertical,10)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(isSelected ? Color.accentColor : .primary)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.windowBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.primary, lineWidth: isSelected ? 2 : 1)
                        }
                        .cornerRadius(8)
                        .onTapGesture {
                            // 点击切换选中状态
                            if selectedCaps.contains(cap) {
                                selectedCaps.remove(cap)
                            } else {
                                selectedCaps.insert(cap)
                            }
                        }
                }
            }
            .padding()
        }
    }
}


struct ReasoningEffortView: View {
    let efforts = ModelReasoningEffort.allCases
    @Binding var selected: Set<ModelReasoningEffort>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Supported reasoning efforts")
                .font(.headline)

            let columns = [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(efforts, id: \.self) { effort in
                    Toggle(effort.name, isOn: binding(for: effort))
                        #if os(macOS)
                        .toggleStyle(.checkbox)          // macOS 原生方形 checkbox
                        #else
                        .toggleStyle(CheckboxStyle())    // iOS 需自定义
                        #endif
                }
            }
        }
        .padding()
    }

    private func binding(for effort: ModelReasoningEffort) -> Binding<Bool> {
        Binding(
            get: { selected.contains(effort) },
            set: { isOn in
                if isOn {
                    selected.insert(effort)
                } else {
                    selected.remove(effort)
                }
            }
        )
    }
}

#if os(iOS)
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn
                      ? "checkmark.square.fill"
                      : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(configuration.isOn ? .accentColor : .secondary)
                configuration.label
            }
        }
        .buttonStyle(.plain) // 去掉 Button 默认高亮，只保留 Toggle 语义
    }
}

#endif
