import SwiftUI
import AgentKit

struct RuntimeServerSettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var isChecking = false
    @State private var isRestarting = false
    @State private var showsDiagnostics = false
    @State private var showsRestartConfirmation = false
    @State private var operationError: String?

    private var coordinator: RuntimeServerCoordinator {
        container.runtimeServers
    }

    private var monitor: RuntimeServerStatusMonitor {
        coordinator.embeddedStatusMonitor
    }

    private var connection: RuntimeServerConnection {
        coordinator.registry.connection(id: RuntimeServerConnection.embeddedID)
            ?? .embedded()
    }

    private var diagnostics: RuntimeServerDiagnosticSnapshot {
        coordinator.embeddedDiagnostics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(verbatim: "服务器")
                .font(.system(size: 30, weight: .semibold))

            embeddedServerCard

            if let operationError {
                Label {
                    Text(verbatim: operationError)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(.red)
            }

            Text(verbatim: "当前版本仅支持 Talkify 内置 Runtime。后续版本将支持连接独立 CodeAgent Server。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 780, alignment: .leading)
        .task {
            await monitorWhileVisible()
        }
        .sheet(isPresented: $showsDiagnostics) {
            RuntimeServerDiagnosticsView(snapshot: diagnostics)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 460)
                #endif
        }
        .alert(isPresented: $showsRestartConfirmation) {
            Alert(
                title: Text(verbatim: "重启内置 Runtime？"),
                message: Text(
                    verbatim: "当前有任务或待处理事项。重启会中断这些任务，且无法自动恢复实时进度。"
                ),
                primaryButton: .destructive(Text(verbatim: "重启")) {
                    Task { await restartEmbedded() }
                },
                secondaryButton: .cancel(Text(verbatim: "取消"))
            )
        }
    }

    private var embeddedServerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(monitor.status.presentation.color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(verbatim: connection.displayName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(verbatim: "当前服务器")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        Text(verbatim: "Embedded")
                        Text(verbatim: "·")
                        Text(verbatim: monitor.status.presentation.title)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isChecking || isRestarting || monitor.status.isTransitional {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()
                .padding(.vertical, 16)

            serverMetadata

            Divider()
                .padding(.vertical, 16)

            HStack(spacing: 10) {
                Button {
                    Task { await checkEmbedded() }
                } label: {
                    Label {
                        Text(verbatim: "重新检查")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isChecking || isRestarting)

                Button {
                    Task { await prepareRestart() }
                } label: {
                    Label {
                        Text(verbatim: "重启 Runtime")
                    } icon: {
                        Image(systemName: "power")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    isChecking
                        || isRestarting
                        || container.providerConnections.isApplyingRuntimeConfiguration
                )

                Spacer()

                Button {
                    showsDiagnostics = true
                } label: {
                    Label {
                        Text(verbatim: "查看诊断")
                    } icon: {
                        Image(systemName: "stethoscope")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    private var serverMetadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            metadataRow(
                title: "Endpoint",
                value: diagnostics.endpoint?.absoluteString ?? "Runtime 未启动"
            )
            metadataRow(
                title: "Runtime Profile",
                value: diagnostics.runtimeProfile?.runtimeProfileDisplayName ?? "未知"
            )
            metadataRow(
                title: "最后连接",
                value: diagnostics.lastConnectedAt?.runtimeServerFormatted ?? "尚未连接"
            )
        }
        .font(.system(size: 13))
    }

    private func metadataRow(title: String, value: String) -> some View {
        GridRow {
            Text(verbatim: title)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func monitorWhileVisible() async {
        while !Task.isCancelled {
            await checkEmbedded()
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
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
            let snapshot = try await container.makeAgentClient().activitySnapshot()
            if ProviderRuntimeActivityPolicy.hasActiveRuntimeWork(snapshot) {
                showsRestartConfirmation = true
            } else {
                await restartEmbedded()
            }
        } catch {
            // If activity cannot be proven idle, require explicit confirmation.
            showsRestartConfirmation = true
        }
    }

    private func restartEmbedded() async {
        guard !isRestarting else { return }
        isRestarting = true
        operationError = nil
        let restarted = await coordinator.restartEmbedded()
        if !restarted {
            operationError = monitor.lastErrorDescription ?? "内置 Runtime 重启失败。"
        }
        isRestarting = false
    }
}

private struct RuntimeServerDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let snapshot: RuntimeServerDiagnosticSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section {
                    diagnosticRow("状态", snapshot.status.presentation.title)
                    diagnosticRow(
                        "Endpoint",
                        snapshot.endpoint?.absoluteString ?? "Runtime 未启动"
                    )
                    diagnosticRow(
                        "Profile",
                        snapshot.runtimeProfile?.runtimeProfileDisplayName ?? "未知"
                    )
                } header: {
                    Text(verbatim: "连接")
                }

                Section {
                    diagnosticRow(
                        "Runtime",
                        snapshot.runtimeInfo?.runtimeVersion ?? "待 Runtime 支持"
                    )
                    diagnosticRow(
                        "Agent Wire",
                        snapshot.runtimeInfo.map {
                            "\($0.agentWireProtocol.major) · \($0.agentWireProtocol.revision)"
                        } ?? "待 Runtime 支持"
                    )
                } header: {
                    Text(verbatim: "版本")
                }

                Section {
                    diagnosticRow(
                        "最后检查",
                        snapshot.lastCheckedAt?.runtimeServerFormatted ?? "尚未检查"
                    )
                    diagnosticRow(
                        "最后连接",
                        snapshot.lastConnectedAt?.runtimeServerFormatted ?? "尚未连接"
                    )
                } header: {
                    Text(verbatim: "时间")
                }

                if let error = snapshot.lastErrorDescription {
                    Section {
                        Text(verbatim: error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } header: {
                        Text(verbatim: "最近错误")
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Runtime 诊断"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: "完成")
                    }
                }
            }
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } label: {
            Text(verbatim: title)
        }
    }
}

private extension RuntimeServerConnectionStatus {
    var presentation: (title: String, color: Color) {
        switch self {
        case .starting:
            ("正在启动", .blue)
        case .checking:
            ("正在检查", .blue)
        case .connected:
            ("已连接", .green)
        case .reconnecting:
            ("正在重连", .orange)
        case .offline:
            ("离线", .gray)
        case .authenticationRequired:
            ("需要认证", .orange)
        case .authenticationFailed:
            ("认证失败", .red)
        case .protocolIncompatible:
            ("协议不兼容", .red)
        case .tlsRequired:
            ("需要 TLS", .red)
        case .configurationError:
            ("配置错误", .red)
        }
    }

    var isTransitional: Bool {
        switch self {
        case .starting, .checking, .reconnecting:
            true
        default:
            false
        }
    }
}

private extension String {
    var runtimeProfileDisplayName: String {
        switch self {
        case "full_desktop":
            "Full Desktop"
        case "sandboxed":
            "Sandboxed"
        case "headless":
            "Headless"
        default:
            self
        }
    }
}

private extension Date {
    var runtimeServerFormatted: String {
        formatted(date: .abbreviated, time: .standard)
    }
}
