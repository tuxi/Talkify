//
//  SettingsDetailView.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/26.
//

import SwiftUI
import CoreKit
import FeatureAuth
import DesignKit
import AgentKit

// MARK: - SettingsDetailView

/// 每个设置分区的内容视图，独立提取以便在 NavigationStack 和 NavigationSplitView 中复用。
struct SettingsDetailView: View {
    @Environment(SettingsRouter.self) private var router
    @Environment(AgentManager.self) private var agentManager
    @Environment(UserManager.self) private var userManager
    @Environment(AuthManager.self) private var authManager
    
    let section: SettingsSection
    
    @AppStorage("settings.defaultPermission") private var defaultPermission = true
    @AppStorage("settings.autoApproval") private var autoApproval = true
    @AppStorage("settings.fullDiskAccess") private var fullDiskAccess = false
    @AppStorage("settings.showInMenuBar") private var showInMenuBar = true
    @AppStorage("settings.showBottomPanel") private var showBottomPanel = true

    @State private var showDeleteAccountAlert = false
    @State private var showDeleteAccountConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    
    public var body: some View {
        contentView
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
            .toolbar {
                if section == .profile {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("分享", systemImage: "square.and.arrow.up") {}
                        Button("私有", systemImage: "lock") {}
                        Button("编辑", systemImage: "pencil") {}
                    }
                }
            }
            .alert("确认删除账号？", isPresented: $showDeleteAccountAlert) {
                Button("取消", role: .cancel) {}
                Button("继续", role: .destructive) {
                    deleteConfirmationText = ""
                    deleteAccountError = nil
                    showDeleteAccountConfirmation = true
                }
            } message: {
                Text("删除账号后，账号资料、登录绑定及相关数据将进入删除流程。该操作通常不可恢复。")
            }
            .sheet(isPresented: $showDeleteAccountConfirmation) {
                DeleteAccountConfirmationSheet(
                    confirmationText: $deleteConfirmationText,
                    isDeleting: isDeletingAccount,
                    errorMessage: deleteAccountError,
                    onCancel: { showDeleteAccountConfirmation = false },
                    onConfirm: { Task { await deleteAccount() } }
                )
#if os(iOS)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
#endif
            }
    }
    
    private var contentView: some View {
        ScrollView(.vertical, content: {
            VStack(alignment: .leading, spacing: 0) {
                switch section {
                case .general:
                    generalSettings
                        .navigationTitle("常规")
                case .profile:
                    profileSettings
                        .navigationTitle("个人资料")
                case .usage:
                    usageBillingSettings
                        .navigationTitle("使用情况和计费")
                case .account:
                    accountSettings
                        .navigationTitle("账户")
                default:
                    unavailableSettings
                        .navigationTitle(section.title)
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 44)
            .padding(.bottom, 56)
        })
        .background(Color.primary.opacity(0.018))
    }
    
    // MARK: - General
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            //            settingsTitle("常规")
            sectionTitle("权限")
            settingsCard {
                SettingsToggleRow(
                    title: "默认权限",
                    description: "默认情况下，Talkify 可以读取和编辑其工作空间中的文件；需要时会请求额外访问权限。",
                    isOn: $defaultPermission
                )
                SettingsToggleRow(
                    title: "自动审核",
                    description: "自动审核额外访问请求，让常规任务流转更顺畅。高风险操作仍会要求你确认。",
                    isOn: $autoApproval
                )
                SettingsToggleRow(
                    title: "完全访问权限",
                    description: "允许在获得授权后访问工作空间之外的文件和命令。启用前请确认你了解相应风险。",
                    isOn: $fullDiskAccess
                )
            }
            
            sectionTitle("常规")
            settingsCard {
                SettingsValueRow(
                    title: "默认文件打开目标",
                    description: "默认打开文件和文件夹的位置"
                ) {
                    Label("Finder", systemImage: "face.smiling")
                        .settingsPickerCapsule()
                }
                SettingsValueRow(title: "语言", description: "应用 UI 语言") {
                    Text("自动检测")
                        .settingsPickerCapsule()
                }
                SettingsToggleRow(
                    title: "在菜单栏中显示",
                    description: "关闭主窗口后，仍在 macOS 菜单栏中保留 Talkify。",
                    isOn: $showInMenuBar
                )
                SettingsToggleRow(
                    title: "底部面板",
                    description: "在应用标题栏中显示底部面板控件。",
                    isOn: $showBottomPanel
                )
            }
        }
    }
    
    // MARK: - Profile
    
    private var profileSettings: some View {
        VStack(spacing: 0) {
            //            Text("个人资料")
            //                .font(.system(size: 19, weight: .semibold))
            //                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(accountInitial)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(Color.accentColor, in: Circle())
                .padding(.top, 66)
            
            Text(accountName)
                .font(.system(size: 32, weight: .regular))
                .padding(.top, 26)
            Text(accountSubtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            
            profileMetricCard
                .padding(.top, 78)
            
            HStack(alignment: .top, spacing: 80) {
                profileActivity
                profileUsageSummary
            }
            .padding(.top, 76)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var profileMetricCard: some View {
        if let usage = agentManager.usage {
            HStack(spacing: 0) {
                ProfileMetric(value: formatted(usage.weekly.unitsUsed), label: "本周用量")
                ProfileMetric(value: formatted(usage.cycle?.unitsUsed ?? 0), label: "订阅周期用量")
                ProfileMetric(value: usage.tier.rawValue.capitalized, label: "当前方案")
            }
            .padding(.vertical, 18)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }
    
    @ViewBuilder
    private var profileActivity: some View {
        if let usage = agentManager.usage {
            VStack(alignment: .leading, spacing: 16) {
                Text("活动洞察")
                    .font(.system(size: 18, weight: .semibold))
                ProfileKeyValue(title: "本周已使用", value: "\(formatted(usage.weekly.unitsUsed)) 单位")
                ProfileKeyValue(title: "当前模型", value: usage.byModel?.first?.model ?? "自动选择")
                ProfileKeyValue(title: "工作区权限", value: defaultPermission ? "已启用" : "按需请求")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var profileUsageSummary: some View {
        if let usage = agentManager.usage {
            VStack(alignment: .leading, spacing: 16) {
                Text("用量")
                    .font(.system(size: 18, weight: .semibold))
                ProfileKeyValue(title: "订阅方案", value: usage.tier.rawValue.capitalized)
                ProfileKeyValue(title: "每周额度", value: weeklyQuotaText)
                ProfileKeyValue(title: "登录状态", value: authManager.isLoggedIn ? "已登录" : "未登录")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Account
    
    private var accountSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountMetaCard
            dangerZoneCard
        }
        .task {
            await userManager.refreshProfileIfNeeded(maxAge: 0)
        }
    }

    private var accountMetaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("账户信息")
            settingsCard {
                SettingsValueRow(title: "昵称", description: "当前登录账户") {
                    Text(accountName).foregroundStyle(.secondary)
                }
                SettingsValueRow(title: "用户 ID", description: "用于识别和支持请求") {
                    HStack(spacing: 8) {
                        Text(userManager.profile?.userId ?? "--")
                            .foregroundStyle(.secondary)
                        if let userID = userManager.profile?.userId {
                            Button {
                                CoreKit.Clipboard.copy(userID)
                                ToastContext.shared.show("已复制")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("复制用户 ID")
                        }
                    }
                }
                SettingsValueRow(title: "注册来源", description: "账号创建方式") {
                    Text(registerSourceText).foregroundStyle(.secondary)
                }
                SettingsValueRow(title: "当前登录方式", description: "已绑定的登录方式") {
                    Text(loginMethodsText).foregroundStyle(.secondary)
                }
                SettingsValueRow(title: "手机号", description: "账号绑定状态") {
                    Text(userManager.profile?.phoneMasked ?? "未绑定")
                        .foregroundStyle(.secondary)
                }
                SettingsValueRow(title: "Apple", description: "账号绑定状态") {
                    Text(userManager.profile?.hasApple == true ? "已绑定" : "未绑定")
                        .foregroundStyle(.secondary)
                }
                if let usage = agentManager.usage {
                    SettingsValueRow(title: "订阅方案", description: "当前服务等级") {
                        Button {
                            if usage.tier == .free {
                                router.presentSheet(.subscription)
                            } else {
                                router.navigate(to: .subscriptionCenter)
                            }
                        } label: {
                            Text(usage.tier.rawValue.capitalized)
                                .settingsPickerCapsule()
                        }
                    }
                }
                Button(role: .destructive) {
                    authManager.logout()
                    userManager.clear()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
    }

    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("危险操作")
            settingsCard {
                VStack(alignment: .leading, spacing: 8) {
//                    Label("删除账号", systemImage: "exclamationmark.triangle.fill")
//                        .font(.system(size: 16, weight: .semibold))
//                        .foregroundStyle(.red)
                    Text("删除账号会清除账号资料、登录绑定和相关数据访问能力。该操作通常不可恢复，请谨慎处理。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("如仅暂时不用，建议先退出登录。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Button(role: .destructive) {
                    showDeleteAccountAlert = true
                } label: {
                    Label(isDeletingAccount ? "正在删除…" : "删除账号", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(isDeletingAccount)
            }
        }
    }
    
    // MARK: - Usage & Billing
    
    private var usageBillingSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            //            settingsTitle("使用情况和计费")
            Text("可在此查看订阅方案、管理订阅并了解当前使用额度。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, -38)
                .padding(.bottom, 58)
            
            if let usage = agentManager.usage {
                sectionTitle("当前套餐")
                settingsCard {
                    SettingsValueRow(title: "\(usage.tier.rawValue.capitalized) 套餐", description: subscriptionDescription(for: usage)) {
                        Button {
                            if usage.tier == .free {
                                router.presentSheet(.subscription)
                            } else {
                                router.navigate(to: .subscriptionCenter)
                            }
                        } label: {
                            Text("查看套餐")
                                .settingsPickerCapsule()
                        }

                    }
                }
                
                sectionTitle("通用使用限额")
                settingsCard {
                    WeeklyQuotaRow(usage: usage.weekly)
                }
                
                if let cycle = usage.cycle {
                    sectionTitle("订阅周期")
                    settingsCard {
                        if let resetsAt = cycle.resetsAt, !resetsAt.isEmpty {
                            SettingsValueRow(title: "订阅周期用量", description: "至 \(formattedResetDate(resetsAt))") {
                                Text("\(formatted(max(cycle.unitsLimit - cycle.unitsUsed, 0))) / \(formatted(cycle.unitsLimit)) 剩余")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            SettingsValueRow(title: "订阅周期用量", description: "") {
                                Text("\(formatted(max(cycle.unitsLimit - cycle.unitsUsed, 0))) / \(formatted(cycle.unitsLimit)) 剩余")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                    }
                }
                
                if !usage.availableResetCards.isEmpty {
                    sectionTitle("使用限制重置")
                    settingsCard {
                        ForEach(usage.availableResetCards) { card in
                            ResetCardSettingsRow(card: card) {
                                agentManager.redeemResetCard(card)
                            }
                        }
                    }
                }
                
                settingsCard {
                    Button {
                        router.navigate(to: .pointsCenter)
                    } label: {
                        HStack(alignment: .center, spacing: 20) {
                            Text("购买点数").font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 21)
                    }
                }
                
            } else {
                ProgressView("正在获取使用情况…")
                    .padding(.top, 24)
            }
        }
        .task {
            agentManager.fetchUsage()
        }
    }
    
    // MARK: - Unavailable
    
    private var unavailableSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            //            settingsTitle(section.title)
            Text("此设置项正在准备中。你可以先在\"常规\"和\"账户\"中调整当前可用的偏好。")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Shared UI helpers
    
    private func settingsTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 34, weight: .semibold))
            .padding(.bottom, 58)
    }
    
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 19, weight: .semibold))
            .padding(.bottom, 28)
    }
    
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .padding(.bottom, 88)
    }
    
    // MARK: - Computed properties
    
    private var accountName: String {
        guard authManager.isLoggedIn else { return "未登录" }
        return authManager.displayNickname ?? userManager.profile?.nickname ?? "Unknow"
    }
    
    private var accountInitial: String { String(accountName.prefix(1)).uppercased() }
    private var accountSubtitle: String { agentManager.usage?.tier.rawValue.capitalized ?? "Talkify 用户" }

    private var registerSourceText: String {
        switch userManager.profile?.registerSource {
        case "phone": return "手机号"
        case "apple": return "Apple"
        case .some(let source) where !source.isEmpty: return source
        default: return "--"
        }
    }

    private var loginMethodsText: String {
        var methods: [String] = []
        if userManager.profile?.hasPhone == true { methods.append("手机号") }
        if userManager.profile?.hasApple == true { methods.append("Apple") }
        if methods.isEmpty, let source = userManager.profile?.registerSource, !source.isEmpty {
            methods.append(registerSourceText)
        }
        return methods.isEmpty ? "--" : methods.joined(separator: "、")
    }

    private func deleteAccount() async {
        let keyword = deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.uppercased() == "DELETE" else {
            deleteAccountError = "请输入正确的确认字样 DELETE"
            return
        }

        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }

        do {
            try await userManager.deleteAccount()
            showDeleteAccountConfirmation = false
            userManager.clear()
            authManager.logout()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }
    
    private var weeklyQuotaText: String {
        guard let usage = agentManager.usage else { return "暂不可用" }
        let remaining = max(usage.weekly.unitsLimit - usage.weekly.unitsUsed, 0)
        return "\(formatted(remaining)) / \(formatted(usage.weekly.unitsLimit)) 剩余"
    }
    
    private func subscriptionDescription(for usage: UsageInfo) -> String {
        usage.tier == .free ? "当前免费服务等级" : "订阅状态正常"
    }
    
    private func formattedResetDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    
    private func formatted(_ value: Int) -> String {
        value >= 1_000_000
        ? String(format: "%.1fM", Double(value) / 1_000_000)
        : (value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)")
    }
}

private struct DeleteAccountConfirmationSheet: View {
    @Binding var confirmationText: String

    let isDeleting: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var isConfirmationFocused: Bool

    private var isConfirmationValid: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("再次确认删除账号", systemImage: "trash.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.red)

            Text("为避免误操作，请输入 DELETE 以确认删除。账号资料、登录绑定及相关数据将进入删除流程。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("请输入 DELETE", text: $confirmationText)
                .textFieldStyle(.roundedBorder)
                .focused($isConfirmationFocused)
#if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
#endif

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)

                Button(role: .destructive, action: onConfirm) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("删除账号")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!isConfirmationValid || isDeleting)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .onAppear { isConfirmationFocused = true }
    }
}

// MARK: - SettingsNavigationDestination + Section

extension SettingsNavigationDestination {
    var section: SettingsSection {
        if case .detail(let section) = self { return section }
        return .general
    }
}

// MARK: - Sidebar Row

struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: section.icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            Text(section.title)
                .font(.system(size: 16, weight: .medium))
            Spacer(minLength: 0)
//            if section == .account { Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(isSelected ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 8)
    }
}

// MARK: - Settings Row Components

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(description).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).padding(.top, 3)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 23)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }
    }
}

private struct SettingsValueRow<Trailing: View>: View {
    let title: String
    let description: String
    @ViewBuilder let trailing: () -> Trailing
    
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(description).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            trailing()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 21)
    }
}

private struct WeeklyQuotaRow: View {
    let usage: UsageInfo.Units
    
    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("每周使用限制")
                    .font(.system(size: 17, weight: .semibold))
                if let resetsAt = usage.resetsAt, !resetsAt.isEmpty {
                    Text("重置\(formattedDate(resetsAt))")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                ProgressView(value: min(max(usage.utilizationPct, 0), 100), total: 100)
                    .tint(usage.utilizationPct >= 90 ? .orange : .primary)
                    .frame(width: 132)
                Text("剩余 \(Int(max(100 - usage.utilizationPct, 0).rounded()))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 21)
    }
    
    private func formattedDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ResetCardSettingsRow: View {
    let card: UsageInfo.ResetCard
    let onRedeem: () -> Void
    @Environment(AgentManager.self) private var agentManager
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Full reset")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(formattedDate(card.expiresAt)) 到期")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            Button(agentManager.isRedeemingResetCard ? "正在使用…" : "使用重置额度") {
                onRedeem()
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .disabled(agentManager.isRedeemingResetCard)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 21)
    }
    
    private func formattedDate(_ value: String?) -> String {
        guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ProfileMetric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 20, weight: .medium)).lineLimit(1)
            Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

private struct ProfileKeyValue: View {
    let title: String
    let value: String
    var body: some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) }
            .font(.system(size: 15))
    }
}

private extension View {
    func settingsPickerCapsule() -> some View {
        HStack(spacing: 8) {
            self
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
        }
        .font(.system(size: 15, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1) }
    }
}
