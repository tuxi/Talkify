#if os(macOS) && TALKIFY_MAC_DIRECT
import SwiftUI
import AppKit
import AgentKit

/// Explicit local owner grant; no model calls or daemon restart.
struct LocalMCPConnectionCommands: Commands {
    let container: AppContainer
    @State private var isWorking = false

    var body: some Commands {
        CommandMenu("Code-Agent MCP") {
            Button("授权本地 MCP 连接…") {
                let alert = NSAlert()
                alert.messageText = "授权本地 MCP 客户端"
                alert.informativeText = "允许本机 MCP Bridge 以 Runtime owner 权限访问当前 Daemon，包括会话与工具控制。这不是仅限单个工作区的凭据。授权 12 小时有效，撤销或 Daemon 重启后失效；本操作不会调用模型。"
                alert.addButton(withTitle: "授权")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                isWorking = true
                Task { @MainActor in
                    defer { isWorking = false }
                    do {
                        guard container.runtimeServers.activeConnectionID == "talkify-local-daemon" else {
                            throw LocalMCPGrantError.unavailable
                        }
                        let url = try await CodeAgentDaemon.shared.exportMCPConnection()
                        guard container.runtimeServers.activeConnectionID == "talkify-local-daemon" else {
                            try? CodeAgentDaemon.shared.revokeMCPConnection()
                            throw LocalMCPGrantError.unavailable
                        }
                        show("本地 MCP 连接已授权", "连接文件：\(url.path)\n仅将文件路径用于 Codex MCP 配置，不要复制文件内容到对话。")
                    } catch { show("无法授权 MCP 连接", error.localizedDescription) }
                }
            }
            .disabled(isWorking || !container.localDaemonReady
                      || container.runtimeServers.activeConnectionID != "talkify-local-daemon")

            Button("撤销本地 MCP 连接") {
                do {
                    try CodeAgentDaemon.shared.revokeMCPConnection()
                    show("本地 MCP 连接已撤销", "Bridge 会在约一秒内停止访问。Daemon 中已执行或已准入的任务不会因此取消。")
                } catch { show("无法撤销 MCP 连接", error.localizedDescription) }
            }
            .disabled(isWorking)
        }
    }

    @MainActor private func show(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
#endif
