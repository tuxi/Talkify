import SwiftUI
import AgentKit

struct ActiveRuntimeServerIndicator: View {
    enum Style {
        case chip
        case sidebar
        case footer
    }

    @Environment(AppContainer.self) private var container

    let style: Style
    let onOpenServers: () -> Void

    private var connection: RuntimeServerConnection? {
        container.runtimeServers.activeConnection
    }

    private var monitor: ExternalRuntimeServerStatusMonitor? {
        guard let connection, connection.kind != .embedded else { return nil }
        return try? container.runtimeServers.externalStatusMonitor(
            connectionID: connection.id
        )
    }

    var body: some View {
        if let connection, connection.kind != .embedded || style == .footer {
            Button(action: onOpenServers) {
                HStack(spacing: 8) {
                    if connection.kind != .embedded {
                        Circle()
                            .fill(statusPresentation.color)
                            .frame(width: 6, height: 6)
                    }

                    Image(systemName: connection.kind == .remote ? "network" : "desktopcomputer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(statusPresentation.title)
                        .font(.system(size: style == .chip ? 12 : 13, weight: .medium))
                        .lineLimit(1)

                    if style == .sidebar {
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, style == .footer ? 0 : style == .chip ? 11 : 12)
                .frame(
                    maxWidth: style == .sidebar ? .infinity : nil,
                    minHeight: style == .sidebar ? 38 : 30,
                    alignment: .leading
                )
                .background {
                    if style != .footer {
                        RoundedRectangle(cornerRadius: style == .chip ? 9 : 11)
                            .fill(.regularMaterial)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开服务器设置")
            .accessibilityLabel("当前服务器：\(statusPresentation.title)")
            .task(id: container.runtimeServers.activeIdentityRevision) {
                await monitorActiveServer()
            }
        }
    }

    private var statusPresentation: (title: String, color: Color) {
        let name = connection?.displayName ?? ""
        guard let monitor else {
            return (name, connection?.kind == .embedded ? .secondary : .orange)
        }
        switch monitor.status {
        case .connected:
            return (name, .green)
        case .starting, .checking, .reconnecting:
            return ("\(name) · 连接中", .orange)
        case .offline:
            return ("\(name) · 离线", .orange)
        case .authenticationRequired, .authenticationFailed:
            return ("\(name) · 认证失败", .red)
        case .protocolIncompatible:
            return ("\(name) · 协议不兼容", .red)
        case .tlsRequired, .configurationError:
            return ("\(name) · 配置错误", .red)
        }
    }

    private func monitorActiveServer() async {
        guard let connection, connection.kind != .embedded else { return }
        while !Task.isCancelled,
              container.runtimeServers.activeConnectionID == connection.id {
            _ = try? await container.runtimeServers.checkExternal(
                connectionID: connection.id
            )
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
        }
    }
}
