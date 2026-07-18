//
//  SettingsView.swift
//  CodeAgent
//

import SwiftUI
import AgentKit
import CoreKit

/// CodeAgent 的桌面设置中心：保持与主工作区一致的双栏信息密度，
/// 同时将常用偏好收拢为可扫描的卡片。
public struct SettingsView: View {
    @Environment(AgentManager.self) private var agentManager
    @Environment(UserManager.self) private var userManager
    @Environment(AuthManager.self) private var authManager

    private let onClose: () -> Void
    @State private var selection: SettingsSection = .general
    @State private var searchText = ""

    @AppStorage("settings.defaultPermission") private var defaultPermission = true
    @AppStorage("settings.autoApproval") private var autoApproval = true
    @AppStorage("settings.fullDiskAccess") private var fullDiskAccess = false
    @AppStorage("settings.showInMenuBar") private var showInMenuBar = true
    @AppStorage("settings.showBottomPanel") private var showBottomPanel = true

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    public var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 350)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            if authManager.isLoggedIn {
                agentManager.fetchUsage()
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            Button(action: onClose) {
                Label("返回应用", systemImage: "arrow.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索设置…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsSection.Group.allCases, id: \.self) { group in
                        let sections = filteredSections(in: group)
                        if !sections.isEmpty {
                            Text(group.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, group == .personal ? 8 : 20)
                                .padding(.bottom, 5)

                            ForEach(sections) { section in
                                Button { selection = section } label: {
                                    SettingsSidebarRow(section: section, isSelected: selection == section)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detailContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                switch selection {
                case .general:
                    generalSettings
                case .profile:
                    profileSettings
                case .usage:
                    usageBillingSettings
                case .account:
                    accountSettings
                default:
                    unavailableSettings
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 44)
            .padding(.bottom, 56)
        }
        .background(Color.primary.opacity(0.018))
        .toolbar {
            if selection == .profile {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("分享", systemImage: "square.and.arrow.up") {}
                    Button("私有", systemImage: "lock") {}
                    Button("编辑", systemImage: "pencil") {}
                }
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle("常规")
            sectionTitle("权限")
            settingsCard {
                SettingsToggleRow(
                    title: "默认权限",
                    description: "默认情况下，CodeAgent 可以读取和编辑其工作空间中的文件；需要时会请求额外访问权限。",
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
                    description: "关闭主窗口后，仍在 macOS 菜单栏中保留 CodeAgent。",
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

    private var profileSettings: some View {
        VStack(spacing: 0) {
            Text("个人资料")
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(accountInitial)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 148, height: 148)
                .background(Color.accentColor, in: Circle())
                .padding(.top, 86)

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

    private var accountSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle("账户")
            sectionTitle("账户信息")
            settingsCard {
                SettingsValueRow(title: "昵称", description: "当前登录账户") {
                    Text(accountName).foregroundStyle(.secondary)
                }
                if let usage = agentManager.usage {
                    SettingsValueRow(title: "订阅方案", description: "当前服务等级") {
                        Text(usage.tier.rawValue.capitalized)
                            .settingsPickerCapsule()
                    }
                }
                Button(role: .destructive) {
                    authManager.logout()
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

    private var usageBillingSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle("使用情况和计费")
            Text("如需管理订阅或购买额外点数，请前往网页端设置。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, -38)
                .padding(.bottom, 58)

            if let usage = agentManager.usage {
                sectionTitle("当前套餐")
                settingsCard {
                    SettingsValueRow(title: "\(usage.tier.rawValue.capitalized) 套餐", description: subscriptionDescription(for: usage)) {
                        Text("查看套餐")
                            .settingsPickerCapsule()
                    }
                }

                sectionTitle("通用使用限额")
                settingsCard {
                    WeeklyQuotaRow(usage: usage.weekly)
                }

                if let cycle = usage.cycle {
                    sectionTitle("订阅周期")
                    settingsCard {
                        SettingsValueRow(title: "订阅周期用量", description: "至 \(formattedResetDate(cycle.resetsAt))") {
                            Text("\(formatted(max(cycle.unitsLimit - cycle.unitsUsed, 0))) / \(formatted(cycle.unitsLimit)) 剩余")
                                .foregroundStyle(.secondary)
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
            } else {
                ProgressView("正在获取使用情况…")
                    .padding(.top, 24)
            }
        }
    }

    private var unavailableSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsTitle(selection.title)
            Text("此设置项正在准备中。你可以先在“常规”和“账户”中调整当前可用的偏好。")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

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

    private func filteredSections(in group: SettingsSection.Group) -> [SettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsSection.allCases.filter {
            $0.group == group && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }
    }

    private var accountName: String {
        guard authManager.isLoggedIn else { return "未登录" }
        
        return authManager.displayNickname ?? userManager.profile?.nickname ?? "Unknow"
    }

    private var accountInitial: String { String(accountName.prefix(1)).uppercased() }
    private var accountSubtitle: String { agentManager.usage?.tier.rawValue.capitalized ?? "CodeAgent 用户" }

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

private enum SettingsSection: String, CaseIterable, Identifiable {
    enum Group: CaseIterable { case personal, integrations, development
        var title: String { switch self { case .personal: "个人"; case .integrations: "集成"; case .development: "编码" } }
    }

    case general, profile, appearance, voice, configuration, personalization, pets, shortcuts, usage, account
    case appSnapshots, plugins, browser, computerControl, hooks, connections, git, environment

    var id: String { rawValue }
    var group: Group {
        switch self {
        case .general, .profile, .appearance, .voice, .configuration, .personalization, .pets, .shortcuts, .usage, .account: .personal
        case .appSnapshots, .plugins, .browser, .computerControl: .integrations
        case .hooks, .connections, .git, .environment: .development
        }
    }
    var title: String {
        switch self {
        case .general: "常规"; case .profile: "个人资料"; case .appearance: "外观"; case .voice: "语音"; case .configuration: "配置"; case .personalization: "个性化"; case .pets: "宠物"; case .shortcuts: "键盘快捷键"; case .usage: "使用情况和计费"; case .account: "账户"; case .appSnapshots: "应用快照"; case .plugins: "插件"; case .browser: "浏览器"; case .computerControl: "电脑操控"; case .hooks: "钩子"; case .connections: "连接"; case .git: "Git"; case .environment: "环境"
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"; case .profile: "person.crop.circle"; case .appearance: "sun.max"; case .voice: "mic"; case .configuration: "shield"; case .personalization: "dial.medium"; case .pets: "pawprint"; case .shortcuts: "command"; case .usage: "chart.bar"; case .account: "person.badge.key"; case .appSnapshots: "viewfinder"; case .plugins: "puzzlepiece"; case .browser: "rectangle"; case .computerControl: "cursorarrow.and.square.on.square.dashed"; case .hooks: "anchor"; case .connections: "globe"; case .git: "point.3.connected.trianglepath.dotted"; case .environment: "laptopcomputer"
        }
    }
}

private struct SettingsSidebarRow: View {
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
            if section == .account { Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(isSelected ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 8)
    }
}

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
        .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }
    }
}

private struct WeeklyQuotaRow: View {
    let usage: UsageInfo.Units

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("每周使用限制")
                    .font(.system(size: 17, weight: .semibold))
                Text("重置时间：\(formattedDate(usage.resetsAt))")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
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
