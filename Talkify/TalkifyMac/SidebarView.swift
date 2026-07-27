//
//  SidebarView.swift
//  AgentKit
//
//  Created by xiaoyuan on 2026/6/24.
//

import SwiftUI
import AgentKit
import CoreKit

/// 最左侧栏：顶部一级 Tab 切换分区，下方为当前分区的会话列表。
/// 列表点选通过 `store.selectedConversation` 驱动中间对话详情。
///
/// - macOS：标准侧栏布局，列表支持 selection 绑定。
/// - iOS：支持搜索过滤、滑动删除，列表点选后自动 push 到详情。
public struct SidebarView: View {
    
    @Environment(WorkspaceStore.self) private var store
    @Environment(AuthManager.self) private var authManager
    @Environment(AgentManager.self) private var agentManager
    @Environment(UserManager.self) private var userManager
    @State private var searchText = ""
    @State private var showAccountPopover = false
    @Binding var showSettings: Bool

    public var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            newTaskButton

            ConversationListView(
                viewModel: store.listViewModel,
                selected: $store.selectedConversation,
                searchText: searchText
            )
        }
        .background(.ultraThinMaterial)
        .navigationTitle(store.selectedTab.title)
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer,
            prompt: TalkifyLocalized.string("workspace.search_placeholder")
        )
        .navigationBarTitleDisplayMode(.large)
        #endif
    }


    private var newTaskButton: some View {
        Button {
            // 仅建立本地草稿；首条消息发送时才会创建真正的会话。
            store.beginDraft()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                Text(verbatim: TalkifyLocalized.string("workspace.new_task"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 10)
        .accessibilityHint(TalkifyLocalized.string("workspace.new_draft_hint"))
    }
}

struct AccountMenuContent: View {
    @Environment(\.dismiss) private var dismiss

    let accountName: String
    let accountInitial: String
    let usage: UsageInfo?
    let isRedeemingResetCard: Bool
    let usageError: String?
    let onContentSizeChange: (CGSize) -> Void
    let onRefreshUsage: () -> Void
    let onRefreshCards: () -> Void
    let onRedeemResetCard: (UsageInfo.ResetCard) -> Void
    let onSettings: () -> Void
    let onLogout: () -> Void

    @State private var isUsageExpanded = false
    @State private var selectedResetCard: UsageInfo.ResetCard?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(accountInitial)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: Circle())
                Text(accountName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isUsageExpanded.toggle()
                }
                if isUsageExpanded {
                    onRefreshUsage()
                    onRefreshCards()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .frame(width: 18)
                    Text(verbatim: TalkifyLocalized.string("workspace.remaining_usage"))
                    Spacer(minLength: 0)
                    Image(systemName: isUsageExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isUsageExpanded {
                usageDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            menuRow(TalkifyLocalized.string("workspace.settings"), systemImage: "gearshape") {
                onSettings()
                dismiss()
            }
            menuRow(TalkifyLocalized.string("workspace.sign_out"), systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                onLogout()
                dismiss()
            }
        }
        .padding(6)
        .frame(width: 280)
        .onAppear { publishContentSize() }
        .onChange(of: isUsageExpanded) { _, _ in publishContentSize() }
        .sheet(item: $selectedResetCard) { card in
            ResetCardSheet(
                card: card,
                isRedeeming: isRedeemingResetCard,
                errorMessage: usageError,
                onRedeem: { onRedeemResetCard(card) }
            )
        }
    }

    private var usageDetails: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let usage {
                usageLine(TalkifyLocalized.string("workspace.week"), metric: usage.weekly)

                if let card = usage.availableResetCards.first {
                    Divider().padding(.vertical, 1)
                    Button { selectedResetCard = card } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: TalkifyLocalized.string("workspace.usage_limit_reset"))
                                Text(String(format: TalkifyLocalized.string("workspace.available_count"), String(usage.resetCards?.availableCount ?? 1), formattedResetDate(card.expiresAt)))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if usage.currentFundingSource == .resetCard {
                    Label(TalkifyLocalized.string("workspace.reset_card_current_week"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: TalkifyLocalized.string("workspace.refreshing_usage")).foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private func usageLine(_ title: String, metric: UsageInfo.Units) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Text("\(formatted(metric.unitsUsed)) / \(formatted(metric.unitsLimit))")
                Text(String(format: "%.1f%%", metric.utilizationPct))
                    .foregroundStyle(metric.utilizationPct >= 90 ? Color.orange : Color.secondary)
            }
            HStack {
                Text(String(format: TalkifyLocalized.string("workspace.remaining_format"), formatted(max(metric.unitsRemaining, 0))))
                Spacer()
                Text(String(format: TalkifyLocalized.string("settings.reset_on"), formattedResetDate(metric.resetsAt)))
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
    }

    private func menuRow(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
    }

    private func formatted(_ value: Int) -> String {
        value >= 1_000_000
            ? String(format: "%.1fM", Double(value) / 1_000_000)
            : (value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)")
    }

    private func formattedResetDate(_ value: String?) -> String {
        guard let value else { return "—" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func publishContentSize() {
        let resetCardHeight = usage?.availableResetCards.isEmpty == false ? 61.0 : 0
        onContentSizeChange(CGSize(width: 300, height: isUsageExpanded ? 245 + resetCardHeight : 184))
    }
}

private struct ResetCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: UsageInfo.ResetCard
    let isRedeeming: Bool
    let errorMessage: String?
    let onRedeem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(TalkifyLocalized.string("workspace.usage"))
                    .font(.system(size: 25, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(TalkifyLocalized.string("workspace.weekly_usage"))
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(TalkifyLocalized.string("workspace.reset_immediately"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Text(TalkifyLocalized.string("workspace.reset_card_desc"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full reset")
                            .font(.system(size: 17, weight: .semibold))
                        Text(String(format: TalkifyLocalized.string("workspace.usage_expires"), formattedDate(card.expiresAt)))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isRedeeming ? TalkifyLocalized.string("workspace.using_reset") : TalkifyLocalized.string("workspace.use_reset")) { onRedeem() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRedeeming)
                }
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(TalkifyLocalized.string("workspace.reset_confirm_warning"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 500)
    }

    private func formattedDate(_ value: String?) -> String {
        guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
