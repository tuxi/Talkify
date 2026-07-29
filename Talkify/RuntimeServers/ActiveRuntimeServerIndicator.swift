import SwiftUI
import AgentKit

struct ActiveRuntimeServerIndicator: View {
    enum Style {
        case chip
        case sidebar
    }

    @Environment(AppContainer.self) private var container

    let style: Style
    let onOpenServers: () -> Void

    private var connection: RuntimeServerConnection {
        container.runtimeServers.activeConnection
    }

    private var monitor: ExternalRuntimeServerStatusMonitor? {
        guard connection.kind != .embedded else { return nil }
        return try? container.runtimeServers.externalStatusMonitor(
            connectionID: connection.id
        )
    }

    var body: some View {
        if connection.kind != .embedded {
            Button(action: onOpenServers) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusPresentation.color)
                        .frame(width: 7, height: 7)

                    Image(systemName: connection.kind == .local ? "desktopcomputer" : "network")
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
                .padding(.horizontal, style == .chip ? 11 : 12)
                .frame(
                    maxWidth: style == .sidebar ? .infinity : nil,
                    minHeight: style == .chip ? 30 : 38,
                    alignment: .leading
                )
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: style == .chip ? 9 : 11,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: style == .chip ? 9 : 11,
                        style: .continuous
                    )
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
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
        guard let monitor else {
            return (connection.displayName, .orange)
        }
        switch monitor.status {
        case .connected:
            return (connection.displayName, .green)
        case .starting, .checking, .reconnecting:
            return ("\(connection.displayName) · 连接中", .orange)
        case .offline:
            return ("\(connection.displayName) · 离线", .orange)
        case .authenticationRequired, .authenticationFailed:
            return ("\(connection.displayName) · 认证失败", .red)
        case .protocolIncompatible:
            return ("\(connection.displayName) · 协议不兼容", .red)
        case .tlsRequired, .configurationError:
            return ("\(connection.displayName) · 配置错误", .red)
        }
    }

    private func monitorActiveServer() async {
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
