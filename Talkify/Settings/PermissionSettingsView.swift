//
//  PermissionSettingsView.swift
//  Talkify
//
//  设置页「权限」分区：按工作区管理审批档位（ask/auto/full）。
//
//  契约：code-agent `GET/PUT /v1/workspaces/permissions/{path}`。
//  见 code-agent docs/approval-modes-client-v1.md §2 入口 B：
//  - 档位是 workspace 级，影响该工作区**所有**对话（不是 per-conversation）。
//  - PUT 不校验 workspace 存在性，任意路径都会凭空创建 settings.local.json，
//    因此这里只列出「已有会话」的工作区（来自 listConversations 去重），避免误创建。
//  - `mode` 是合并后的有效档位（workspace 未设置时含 user 层 fallback）；
//    v1 响应无来源字段，无法区分「自定义」vs「继承全局」。
//

import SwiftUI
import AgentKit
import CoreKit
import DesignKit

/// 设置页「权限」分区。
struct PermissionSettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var client: (any RuntimeClient)?
    @State private var rows: [PermissionRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// 单个工作区的档位行。
    struct PermissionRow: Identifiable {
        let id: String // workspacePath
        let path: String
        var mode: String
        var modes: [String]
        var isUpdating = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("对话所属工作区的审批档位。档位影响该工作区的所有对话：请求批准（ask，每次询问）、帮我批准（auto，工作区内自动、网络命令与 MCP 工具询问）、完全访问（full，全部自动）。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载工作区权限…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("暂无工作区", systemImage: "shield")
                } description: {
                    Text("创建对话后，这里会显示其工作区的权限档位。")
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 0) {
                    ForEach($rows) { $row in
                        permissionRow($row)
                        if row.id != rows.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(
                    Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .task { await load() }
    }

    // MARK: - Row

    private func permissionRow(_ row: Binding<PermissionRow>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(row.wrappedValue.path))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(row.wrappedValue.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Picker("", selection: row.mode) {
                ForEach(row.wrappedValue.modes, id: \.self) { mode in
                    Text(modeTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(row.wrappedValue.isUpdating)
            .onChange(of: row.wrappedValue.mode) { _, newMode in
                Task { await setMode(row: row, mode: newMode) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Data

    private func load() async {
        guard let client = try? await resolveClient() else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let conversations = try await client.listConversations()
            var paths: [String] = []
            var seen = Set<String>()
            for conversation in conversations where !conversation.workspacePath.isEmpty {
                if seen.insert(conversation.workspacePath).inserted {
                    paths.append(conversation.workspacePath)
                }
            }
            var loaded: [PermissionRow] = []
            for path in paths {
                if let permissions = try? await client.getWorkspacePermissions(workspacePath: path) {
                    loaded.append(PermissionRow(
                        id: path,
                        path: path,
                        mode: permissions.mode,
                        modes: permissions.available.isEmpty ? ["ask", "auto", "full"] : permissions.available
                    ))
                }
            }
            loaded.sort { $0.path < $1.path }
            rows = loaded
            errorMessage = nil
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private func setMode(row: Binding<PermissionRow>, mode: String) async {
        guard let client else { return }
        row.wrappedValue.isUpdating = true
        defer { row.wrappedValue.isUpdating = false }
        do {
            let permissions = try await client.setWorkspacePermissions(
                workspacePath: row.wrappedValue.path,
                mode: mode
            )
            row.wrappedValue.mode = permissions.mode
            if !permissions.available.isEmpty {
                row.wrappedValue.modes = permissions.available
            }
            errorMessage = nil
        } catch {
            errorMessage = "设置失败：\(error.localizedDescription)"
            await load()
        }
    }

    /// 惰性创建 active runtime client；无活跃服务时优雅降级。
    private func resolveClient() async throws -> any RuntimeClient {
        if let client { return client }
        let client = container.makeAgentClient()
        self.client = client
        return client
    }

    private func displayName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode {
        case "auto": return "帮我批准 (Auto)"
        case "full": return "完全访问 (Full)"
        default: return "请求批准 (Ask)"
        }
    }
}
