import SwiftUI
import AgentKit

struct RuntimeServerSettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var editorRequest: RuntimeServerEditorRequest?
    @State private var diagnosticsRequest: RuntimeServerDiagnosticsRequest?
    @State private var pendingSwitch: RuntimeServerConnection?
    @State private var pendingRemoval: RuntimeServerConnection?
    @State private var isSwitching = false
    @State private var operationError: String?

    private var coordinator: RuntimeServerCoordinator {
        container.runtimeServers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Text(verbatim: "服务器")
                    .font(.system(size: 30, weight: .semibold))
                Spacer()
                Button {
                    editorRequest = .add
                } label: {
                    Label("添加服务器", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 12) {
                ForEach(coordinator.registry.connections) { connection in
                    serverCard(connection)
                }
            }

            if let operationError {
                Label(operationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("一次只连接一台服务器。切换不会停止旧服务器上的任务，也不会迁移会话或模型。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 780, alignment: .leading)
        .task(id: registeredServerIDs) {
            await monitorWhileVisible()
        }
        .sheet(item: $editorRequest) { request in
            RuntimeServerEditorView(request: request)
                .environment(container)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .sheet(item: $diagnosticsRequest) { request in
            RuntimeServerDiagnosticsView(snapshot: request.snapshot)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 480)
                #endif
        }
        .alert(
            "切换服务器？",
            isPresented: Binding(
                get: { pendingSwitch != nil },
                set: { if !$0 { pendingSwitch = nil } }
            ),
            presenting: pendingSwitch
        ) { connection in
            Button("取消", role: .cancel) {}
            Button("切换") {
                Task { await activate(connection, confirmed: true) }
            }
        } message: { _ in
            Text("切换后，当前服务器上的任务会继续运行；Talkify 将停止显示其实时进度，重新切回后可恢复查看。")
        }
        .alert(
            "删除服务器？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { connection in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await remove(connection) }
            }
        } message: { connection in
            Text("将删除“\(connection.displayName)”的本地连接记录和 Access Token，不会删除服务器上的会话或数据。")
        }
    }

    private var registeredServerIDs: String {
        coordinator.registry.connections.map(\.id).joined(separator: ",")
    }

    @ViewBuilder
    private func serverCard(_ connection: RuntimeServerConnection) -> some View {
        if connection.kind == .embedded {
            EmbeddedRuntimeServerCard(
                connection: connection,
                isActive: coordinator.activeConnectionID == connection.id,
                onActivate: { Task { await prepareActivation(connection) } },
                onDiagnostics: {
                    diagnosticsRequest = RuntimeServerDiagnosticsRequest(
                        snapshot: coordinator.embeddedDiagnostics
                    )
                }
            )
        } else if let monitor = try? coordinator.externalStatusMonitor(
            connectionID: connection.id
        ) {
            ExternalRuntimeServerCard(
                connection: connection,
                monitor: monitor,
                isActive: coordinator.activeConnectionID == connection.id,
                isSwitching: isSwitching,
                onCheck: { Task { await checkExternal(connection) } },
                onActivate: { Task { await prepareActivation(connection) } },
                onEdit: { editorRequest = .edit(connection) },
                onRemove: { pendingRemoval = connection },
                onDiagnostics: {
                    diagnosticsRequest = RuntimeServerDiagnosticsRequest(
                        snapshot: monitor.diagnosticSnapshot
                    )
                }
            )
        }
    }

    private func monitorWhileVisible() async {
        while !Task.isCancelled {
            _ = await coordinator.checkEmbedded()
            for connection in coordinator.registry.connections
            where connection.kind != .embedded {
                _ = try? await coordinator.checkExternal(connectionID: connection.id)
            }
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
        }
    }

    private func checkExternal(_ connection: RuntimeServerConnection) async {
        operationError = nil
        do {
            let healthy = try await coordinator.checkExternal(connectionID: connection.id)
            if !healthy,
               let monitor = try? coordinator.externalStatusMonitor(
                   connectionID: connection.id
               ) {
                operationError = monitor.lastErrorDescription
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func prepareActivation(_ connection: RuntimeServerConnection) async {
        guard connection.id != coordinator.activeConnectionID, !isSwitching else { return }
        operationError = nil
        isSwitching = true
        defer { isSwitching = false }
        do {
            let snapshot = try await container.makeAgentClient().activitySnapshot()
            if ProviderRuntimeActivityPolicy.hasActiveRuntimeWork(snapshot) {
                pendingSwitch = connection
            } else {
                // The host has already applied the protocol-correct `queue > 0`
                // activity policy. Passing confirmation here avoids treating an
                // idle queue position of zero as active work in older runtimes.
                try await container.activateRuntimeServer(
                    connectionID: connection.id,
                    allowingActiveWorkInterruption: true
                )
            }
        } catch {
            // An unreachable current Server cannot prove active work. Switching
            // remains explicit and does not cancel work on the old Server.
            do {
                try await container.activateRuntimeServer(
                    connectionID: connection.id,
                    allowingActiveWorkInterruption: true
                )
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func activate(
        _ connection: RuntimeServerConnection,
        confirmed: Bool
    ) async {
        guard !isSwitching else { return }
        operationError = nil
        isSwitching = true
        defer {
            isSwitching = false
            pendingSwitch = nil
        }
        do {
            try await container.activateRuntimeServer(
                connectionID: connection.id,
                allowingActiveWorkInterruption: confirmed
            )
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func remove(_ connection: RuntimeServerConnection) async {
        operationError = nil
        defer { pendingRemoval = nil }
        do {
            try await coordinator.removeExternalConnection(connectionID: connection.id)
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct EmbeddedRuntimeServerCard: View {
    @Environment(AppContainer.self) private var container

    let connection: RuntimeServerConnection
    let isActive: Bool
    let onActivate: () -> Void
    let onDiagnostics: () -> Void

    @State private var isChecking = false
    @State private var isRestarting = false
    @State private var showsRestartConfirmation = false
    @State private var operationError: String?

    private var coordinator: RuntimeServerCoordinator {
        container.runtimeServers
    }

    private var monitor: RuntimeServerStatusMonitor {
        coordinator.embeddedStatusMonitor
    }

    var body: some View {
        RuntimeServerCardShell(
            title: connection.displayName,
            subtitle: "Embedded · \(monitor.status.presentation.title)",
            statusColor: monitor.status.presentation.color,
            isActive: isActive
        ) {
            RuntimeServerMetadataGrid(
                endpoint: coordinator.embeddedDiagnostics.endpoint?.absoluteString
                    ?? "Runtime 未启动",
                profile: coordinator.embeddedDiagnostics.runtimeProfile?
                    .runtimeProfileDisplayName ?? "未知",
                lastConnectedAt: coordinator.embeddedDiagnostics.lastConnectedAt
            )

            HStack(spacing: 10) {
                if !isActive {
                    Button("设为当前服务器", action: onActivate)
                        .buttonStyle(.borderedProminent)
                }
                Button {
                    Task { await checkEmbedded() }
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isChecking || isRestarting)

                Button {
                    Task { await prepareRestart() }
                } label: {
                    Label("重启 Runtime", systemImage: "power")
                }
                .buttonStyle(.bordered)
                .disabled(
                    isChecking
                        || isRestarting
                        || container.providerConnections.isApplyingRuntimeConfiguration
                )

                Spacer()
                Button("查看诊断", action: onDiagnostics)
                    .buttonStyle(.borderless)
            }

            if let operationError {
                Text(operationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .alert("重启内置 Runtime？", isPresented: $showsRestartConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重启", role: .destructive) {
                Task { await restartEmbedded() }
            }
        } message: {
            Text("当前有任务或待处理事项。重启会中断这些任务，且无法自动恢复实时进度。")
        }
    }

    private func checkEmbedded() async {
        guard !isChecking, !isRestarting else { return }
        isChecking = true
        operationError = nil
        _ = await coordinator.checkEmbedded()
        isChecking = false
    }

    private func prepareRestart() async {
        guard !isChecking,
              !isRestarting,
              !container.providerConnections.isApplyingRuntimeConfiguration else {
            return
        }
        operationError = nil
        if monitor.status == .offline || monitor.status == .configurationError {
            await restartEmbedded()
            return
        }
        do {
            let snapshot = try await coordinator.makeClient(
                connection: connection
            ).activitySnapshot()
            if ProviderRuntimeActivityPolicy.hasActiveRuntimeWork(snapshot) {
                showsRestartConfirmation = true
            } else {
                await restartEmbedded()
            }
        } catch {
            showsRestartConfirmation = true
        }
    }

    private func restartEmbedded() async {
        guard !isRestarting else { return }
        isRestarting = true
        operationError = nil
        let restarted = await coordinator.restartEmbedded()
        if restarted {
            if isActive {
                await container.refreshActiveRuntimeContext()
            }
        } else {
            operationError = monitor.lastErrorDescription ?? "内置 Runtime 重启失败。"
        }
        isRestarting = false
    }
}

private struct ExternalRuntimeServerCard: View {
    let connection: RuntimeServerConnection
    let monitor: ExternalRuntimeServerStatusMonitor
    let isActive: Bool
    let isSwitching: Bool
    let onCheck: () -> Void
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onDiagnostics: () -> Void

    var body: some View {
        RuntimeServerCardShell(
            title: connection.displayName,
            subtitle: "\(connection.kind.displayName) · \(monitor.status.presentation.title)",
            statusColor: monitor.status.presentation.color,
            isActive: isActive
        ) {
            RuntimeServerMetadataGrid(
                endpoint: connection.endpoint?.absoluteString ?? "未知",
                profile: monitor.runtimeInfo?.runtimeProfile
                    .runtimeProfileDisplayName ?? "未知",
                lastConnectedAt: monitor.lastConnectedAt
            )

            if monitor.status != .connected, let lastConnectedAt = monitor.lastConnectedAt {
                Label(
                    "离线时仅可浏览已落盘的本地缓存（只读）。上次同步：\(lastConnectedAt.runtimeServerFormatted)",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if !isActive {
                    Button("设为当前服务器", action: onActivate)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSwitching)
                }
                Button("重新检查", action: onCheck)
                    .buttonStyle(.bordered)
                    .disabled(monitor.status == .checking)
                Button("编辑", action: onEdit)
                    .buttonStyle(.bordered)

                Spacer()
                Button("查看诊断", action: onDiagnostics)
                    .buttonStyle(.borderless)
                if !isActive {
                    Button("删除", role: .destructive, action: onRemove)
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct RuntimeServerCardShell<Content: View>: View {
    let title: String
    let subtitle: String
    let statusColor: Color
    let isActive: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        statusColor: Color,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusColor = statusColor
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                        if isActive {
                            Text("当前服务器")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        }
    }
}

private struct RuntimeServerMetadataGrid: View {
    let endpoint: String
    let profile: String
    let lastConnectedAt: Date?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            row("Endpoint", endpoint)
            row("Runtime Profile", profile)
            row("最后连接", lastConnectedAt?.runtimeServerFormatted ?? "尚未连接")
        }
        .font(.system(size: 13))
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private enum RuntimeServerEditorRequest: Identifiable {
    case add
    case edit(RuntimeServerConnection)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let connection): "edit-\(connection.id)-\(connection.updatedAt.timeIntervalSince1970)"
        }
    }

    var connection: RuntimeServerConnection? {
        guard case .edit(let connection) = self else { return nil }
        return connection
    }
}

private struct RuntimeServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    let request: RuntimeServerEditorRequest

    @State private var endpointText: String
    @State private var displayName: String
    @State private var authentication: RuntimeServerAuthentication
    @State private var accessToken = ""
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var testedResult: RuntimeServerPreflightResult?
    @State private var pendingIdentityResult: RuntimeServerPreflightResult?

    init(request: RuntimeServerEditorRequest) {
        self.request = request
        let connection = request.connection
        _endpointText = State(initialValue: connection?.endpoint?.absoluteString ?? "")
        _displayName = State(initialValue: connection?.displayName ?? "")
        _authentication = State(initialValue: connection?.authentication ?? .bearer)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    serverFields
                    authenticationFields
                    securityNotice

                    if let testedResult {
                        preflightResultCard(testedResult)
                    }
                    if let errorMessage {
                        errorCard(errorMessage)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }

            Divider()
            editorFooter
        }
        .background(Color.platformRuntimeEditorBackground)
        #if os(macOS)
        .frame(width: 620, height: testedResult == nil && errorMessage == nil ? 570 : 680)
        #endif
        .alert(
            "服务器身份已变化",
            isPresented: Binding(
                get: { pendingIdentityResult != nil },
                set: { if !$0 { pendingIdentityResult = nil } }
            )
        ) {
            Button("取消", role: .cancel) {}
            Button("确认并保存", role: .destructive) {
                Task { await saveConfirmedIdentity() }
            }
        } message: {
            Text("该地址返回了不同的 Server ID。仅在你确认服务器已重建或更换后继续。")
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: request.connection == nil ? "server.rack" : "server.rack")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(request.connection == nil ? "添加服务器" : "编辑服务器")
                    .font(.system(size: 18, weight: .semibold))
                Text("连接兼容 Agent Wire 协议的 CodeAgent Runtime")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var serverFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorSectionTitle("服务器")

            editorField("服务器 URL", caption: "CodeAgent Runtime 的 HTTP(S) 地址") {
                TextField("例如 http://127.0.0.1:8797", text: $endpointText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    .runtimeEditorTextField()
            }

            editorField("显示名称", caption: "可选；留空时使用服务器返回的名称") {
                TextField("例如 Mac Studio", text: $displayName)
                    .runtimeEditorTextField()
            }
        }
    }

    private var authenticationFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorSectionTitle("访问控制")

            Picker("认证方式", selection: $authentication) {
                Text("Access Token").tag(RuntimeServerAuthentication.bearer)
                Text("无认证").tag(RuntimeServerAuthentication.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if authentication == .bearer {
                editorField(
                    "Access Token",
                    caption: request.connection == nil
                        ? "Token 至少需要 32 字节，并仅保存在系统 Keychain"
                        : "留空会继续使用 Keychain 中已有的 Token"
                ) {
                    SecureField("输入服务器 Access Token", text: $accessToken)
                        .runtimeEditorTextField()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: authentication)
    }

    private var securityNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            Text(securityNoticeText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var securityNoticeText: String {
        #if os(iOS)
        "localhost 指当前 iPhone，请填写 Mac 的局域网、VPN 或域名地址。远程服务器必须使用 HTTPS。"
        #else
        "本机 loopback 地址可使用 HTTP。局域网或远程服务器必须使用 HTTPS 和 Access Token。"
        #endif
    }

    private var editorFooter: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                Task { await testAndSave() }
            } label: {
                HStack(spacing: 8) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.circle")
                    }
                    Text(isTesting ? "正在测试连接…" : "测试连接并保存")
                }
                .frame(minWidth: 150)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isTesting || endpointText.trimmed.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func editorSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func editorField<Content: View>(
        _ title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            }
            content()
        }
    }

    private func preflightResultCard(
        _ result: RuntimeServerPreflightResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("连接成功", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                preflightRow("服务器", result.info.displayName)
                preflightRow("Runtime", result.info.runtimeVersion)
                preflightRow(
                    "Agent Wire",
                    "\(result.info.agentWireProtocol.major) · \(result.info.agentWireProtocol.revision)"
                )
                preflightRow(
                    "模型",
                    "\(result.modelCatalog.unifiedModels(serverConnectionID: nil).count) 个"
                )
                preflightRow("Server ID", result.info.serverID)
            }
            .font(.system(size: 12))
        }
        .padding(15)
        .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.20), lineWidth: 1)
        }
    }

    private func preflightRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 12))
        .foregroundStyle(.red)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func testAndSave() async {
        guard let endpoint = URL(string: endpointText.trimmed) else {
            errorMessage = "请输入有效的服务器 URL。"
            return
        }
        isTesting = true
        errorMessage = nil
        testedResult = nil
        defer { isTesting = false }
        do {
            let result = try await container.runtimeServers.preflightExternal(
                connectionID: request.connection?.id,
                endpoint: endpoint,
                authentication: authentication,
                accessToken: accessToken.trimmed.nilIfEmpty
            )
            testedResult = result
            do {
                try await save(result, confirmIdentityChange: false)
            } catch RuntimeServerCoordinatorError.identityConfirmationRequired {
                pendingIdentityResult = result
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveConfirmedIdentity() async {
        guard let result = pendingIdentityResult else { return }
        pendingIdentityResult = nil
        isTesting = true
        defer { isTesting = false }
        do {
            try await save(result, confirmIdentityChange: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(
        _ result: RuntimeServerPreflightResult,
        confirmIdentityChange: Bool
    ) async throws {
        let id = request.connection?.id ?? "runtime-server-\(UUID().uuidString.lowercased())"
        let connection = try await container.runtimeServers.saveExternalConnection(
            id: id,
            displayName: displayName.trimmed.nilIfEmpty,
            preflight: result,
            accessToken: accessToken.trimmed.nilIfEmpty,
            confirmIdentityChange: confirmIdentityChange
        )
        if connection.id == container.runtimeServers.activeConnectionID {
            await container.refreshActiveRuntimeContext()
        }
        dismiss()
    }
}

private struct RuntimeServerDiagnosticsRequest: Identifiable {
    let id = UUID()
    let snapshot: RuntimeServerDiagnosticSnapshot
}

private struct RuntimeServerDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let snapshot: RuntimeServerDiagnosticSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section("连接") {
                    row("状态", snapshot.status.presentation.title)
                    row("Endpoint", snapshot.endpoint?.absoluteString ?? "Runtime 未启动")
                    row(
                        "Profile",
                        snapshot.runtimeProfile?.runtimeProfileDisplayName ?? "未知"
                    )
                }
                Section("版本") {
                    row("Runtime", snapshot.runtimeInfo?.runtimeVersion ?? "未知")
                    row(
                        "Agent Wire",
                        snapshot.runtimeInfo.map {
                            "\($0.agentWireProtocol.major) · \($0.agentWireProtocol.revision)"
                        } ?? "未知"
                    )
                    if let serverID = snapshot.runtimeInfo?.serverID {
                        row("Server ID", serverID)
                    }
                }
                Section("时间") {
                    row(
                        "最后检查",
                        snapshot.lastCheckedAt?.runtimeServerFormatted ?? "尚未检查"
                    )
                    row(
                        "最后连接",
                        snapshot.lastConnectedAt?.runtimeServerFormatted ?? "尚未连接"
                    )
                }
                if let error = snapshot.lastErrorDescription {
                    Section("最近错误") {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Runtime 诊断")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }
}

private extension RuntimeServerConnectionStatus {
    var presentation: (title: String, color: Color) {
        switch self {
        case .starting: ("正在启动", .blue)
        case .checking: ("正在检查", .blue)
        case .connected: ("已连接", .green)
        case .reconnecting: ("正在重连", .orange)
        case .offline: ("离线", .gray)
        case .authenticationRequired: ("需要认证", .orange)
        case .authenticationFailed: ("认证失败", .red)
        case .protocolIncompatible: ("协议不兼容", .red)
        case .tlsRequired: ("需要 TLS", .red)
        case .configurationError: ("配置错误", .red)
        }
    }
}

private extension RuntimeServerKind {
    var displayName: String {
        switch self {
        case .embedded: "Embedded"
        case .local: "Local"
        case .remote: "Remote"
        }
    }
}

private extension String {
    var runtimeProfileDisplayName: String {
        switch self {
        case "full_desktop": "Full Desktop"
        case "sandboxed": "Sandboxed"
        case "headless": "Headless"
        default: self
        }
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Date {
    var runtimeServerFormatted: String {
        formatted(date: .abbreviated, time: .standard)
    }
}

private extension View {
    func runtimeEditorTextField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

private extension Color {
    static var platformRuntimeEditorBackground: Color {
        Color.primary.opacity(0.012)
    }
}
