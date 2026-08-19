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
import FileViewerKit

// MARK: - SettingsDetailView

/// 每个设置分区的内容视图，独立提取以便在 NavigationStack 和 NavigationSplitView 中复用。
struct SettingsDetailView: View {
    
    @Environment(\.openURL) private var openURL
    
    @Environment(SettingsRouter.self) private var router
    @Environment(AgentManager.self) private var agentManager
    @Environment(UserManager.self) private var userManager
    @Environment(AuthManager.self) private var authManager
    @Environment(AppContainer.self) private var container
    
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
    @State private var tokenActivityTab: TokenActivityTab = .daily
    
    public var body: some View {
        contentView
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
            .alert(TalkifyLocalized.string("settings.delete_account_confirm"), isPresented: $showDeleteAccountAlert) {
                Button(TalkifyLocalized.string("common.action.cancel"), role: .cancel) {}
                Button(TalkifyLocalized.string("common.action.continue"), role: .destructive) {
                    deleteConfirmationText = ""
                    deleteAccountError = nil
                    showDeleteAccountConfirmation = true
                }
            } message: {
                Text(verbatim: TalkifyLocalized.string("settings.delete_account_warning"))
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
                case .profile:
                    if authManager.isRegistered {
                        profileSettings
                            .navigationTitle(TalkifyLocalized.string("settings.item.profile"))
                    } else {
                        gatewayDisconnectedView
                            .navigationTitle(TalkifyLocalized.string("settings.item.profile"))
                    }
                case .usage:
                    if authManager.isRegistered {
                        usageBillingSettings
                            .navigationTitle(TalkifyLocalized.string("settings.item.usage"))
                    } else {
                        gatewayDisconnectedView
                            .navigationTitle(TalkifyLocalized.string("settings.item.usage"))
                    }
                case .account:
                    if authManager.isRegistered {
                        accountSettings
                            .navigationTitle(TalkifyLocalized.string("settings.item.account"))
                    } else {
                        gatewayDisconnectedView
                            .navigationTitle(TalkifyLocalized.string("settings.item.account"))
                    }
                case .servers:
                    RuntimeServerSettingsView()
                        .navigationTitle(Text(verbatim: "服务器"))
                case .providers:
                    ProviderSettingsView()
                        .navigationTitle("提供商")
                case .models:
                    ModelCatalogSettingsView()
                        .navigationTitle("模型")
                case .settings:
#if os(macOS)
                    let home = FileManager.default.homeDirectoryForCurrentUser
#else
                    let cfg = EmbeddedRuntimeConfiguration.platformDefault()
                    let home = cfg.dataDirectory
                    
#endif
                    let root = home.appendingPathComponent(".codeagent")
                    
                    SettingsFileWorkspaceContainer(rootURL: root)
                        .navigationTitle(TalkifyLocalized.string("settings.item.config"))
                case .support:
                    supportSettings
                        .navigationTitle(TalkifyLocalized.string("settings.item.support"))
                case .about:
                    aboutSettings
                        .navigationTitle(TalkifyLocalized.string("settings.item.about"))
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 44)
            .padding(.bottom, 56)
        })
        .background(Color.primary.opacity(0.018))
    }

    private var gatewayDisconnectedView: some View {
        ContentUnavailableView {
            Label("未连接 Talkify Gateway", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("连接 Talkify Gateway 后查看账户、订阅、余额和用量。")
        } actions: {
            Button("连接 Talkify Gateway") {
                authManager.requireLogin()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
    
    // MARK: - General
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            //            settingsTitle("常规")
            sectionTitle(TalkifyLocalized.string("settings.permissions"))
            settingsCard {
                SettingsToggleRow(
                    title: TalkifyLocalized.string("settings.default_permission"),
                    description: TalkifyLocalized.string("settings.default_permission_desc"),
                    isOn: $defaultPermission
                )
                SettingsToggleRow(
                    title: TalkifyLocalized.string("settings.auto_review"),
                    description: TalkifyLocalized.string("settings.auto_review_desc"),
                    isOn: $autoApproval
                )
                SettingsToggleRow(
                    title: TalkifyLocalized.string("settings.full_access"),
                    description: TalkifyLocalized.string("settings.full_access_desc"),
                    isOn: $fullDiskAccess
                )
            }
            
            sectionTitle(TalkifyLocalized.string("settings.item.general"))
            settingsCard {
                SettingsValueRow(
                    title: TalkifyLocalized.string("settings.default_file_target"),
                    description: TalkifyLocalized.string("settings.default_file_target_desc")
                ) {
                    Label("Finder", systemImage: "face.smiling")
                        .settingsPickerCapsule()
                }
                SettingsValueRow(title: TalkifyLocalized.string("settings.language"), description: TalkifyLocalized.string("settings.app_ui_language")) {
                    Text(verbatim: TalkifyLocalized.string("settings.auto_detect"))
                        .settingsPickerCapsule()
                }
                SettingsToggleRow(
                    title: TalkifyLocalized.string("settings.show_in_menu_bar"),
                    description: TalkifyLocalized.string("settings.show_in_menu_bar_desc"),
                    isOn: $showInMenuBar
                )
                SettingsToggleRow(
                    title: TalkifyLocalized.string("settings.bottom_panel"),
                    description: TalkifyLocalized.string("settings.bottom_panel_desc"),
                    isOn: $showBottomPanel
                )
            }
        }
    }
    
    // MARK: - Profile
    
    private var profileSettings: some View {
        VStack(spacing: 0) {
            Text(accountInitial)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(Color.accentColor, in: Circle())
                .padding(.top, 48)
            
            Text(accountName)
                .font(.system(size: 32, weight: .regular))
                .padding(.top, 20)
            Text(accountSubtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            
            if let usage = agentManager.usage {
                profileStatsGrid(usage: usage)
                    .padding(.top, 44)
                
                tokenActivitySection(usage: usage)
                    .padding(.top, 60)
                
                activityInsightsSection(usage: usage)
                    .padding(.top, 44)
#if DEBUG
                quickModeBanner
                    .padding(.top, 44)
#endif
            }
        }
        .padding(.bottom, 56)
    }
    
    // MARK: - Stats Grid (2x3)
    
    private func profileStatsGrid(usage: UsageInfo) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)],
            spacing: 28
        ) {
            ProfileStatCell(
                value: formattedCN(usage.weekly.tokensUsed),
                label: TalkifyLocalized.string("settings.cumulative_tokens")
            )
            ProfileStatCell(
                value: formattedCN(usage.weekly.tokensUsed),
                label: TalkifyLocalized.string("settings.peak_tokens")
            )
            ProfileStatCell(
                value: "\(usage.weekly.unitsUsed)",
                label: TalkifyLocalized.string("settings.this_week_usage")
            )
            ProfileStatCell(
                value: "\(max(usage.weekly.unitsLimit - usage.weekly.unitsUsed, 0))",
                label: TalkifyLocalized.string("settings.weekly_quota")
            )
            ProfileStatCell(
                value: "\(usage.byModel?.count ?? 0)",
                label: TalkifyLocalized.string("settings.available_models")
            )
            ProfileStatCell(
                value: usage.tier.rawValue.capitalized,
                label: TalkifyLocalized.string("settings.current_tier")
            )
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }
    
    // MARK: - Token Activity
    
    private func tokenActivitySection(usage: UsageInfo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: TalkifyLocalized.string("settings.token_activity"))
                .font(.system(size: 18, weight: .semibold))
            
            HStack(spacing: 8) {
                ForEach([TokenActivityTab.daily, .weekly, .cumulative], id: \.self) { tab in
                    tokenActivityPill(tab, selected: tokenActivityTab == tab)
                        .onTapGesture { tokenActivityTab = tab }
                }
            }
            
            VStack(alignment: .leading, spacing: 14) {
                ProfileKeyValue(
                    title: TalkifyLocalized.string("settings.used_this_week_label"),
                    value: formattedCN(usage.weekly.tokensUsed) + " Token"
                )
                if let modelUsage = usage.byModel?.first {
                    ProfileKeyValue(
                        title: TalkifyLocalized.string("settings.current_model"),
                        value: modelUsage.model
                    )
                }
                ProfileKeyValue(
                    title: TalkifyLocalized.string("settings.weekly_quota"),
                    value: String(
                        format: TalkifyLocalized.string("settings.cycle_remaining_format"),
                        formatted(max(usage.weekly.unitsLimit - usage.weekly.unitsUsed, 0)),
                        formatted(usage.weekly.unitsLimit)
                    )
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func tokenActivityPill(_ tab: TokenActivityTab, selected: Bool) -> some View {
        Text(tab.label)
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                selected
                    ? Color.accentColor
                    : Color.primary.opacity(0.08),
                in: Capsule()
            )
    }
    
    // MARK: - Activity Insights
    
    private func activityInsightsSection(usage: UsageInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: TalkifyLocalized.string("settings.activity_insights"))
                .font(.system(size: 18, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 14) {
                ProfileKeyValue(
                    title: TalkifyLocalized.string("settings.current_model"),
                    value: usage.byModel?.first?.model ?? TalkifyLocalized.string("settings.auto_select")
                )
                ProfileKeyValue(
                    title: TalkifyLocalized.string("settings.workspace_permission"),
                    value: defaultPermission ? TalkifyLocalized.string("settings.enabled") : TalkifyLocalized.string("settings.on_demand")
                )
                ProfileKeyValue(
                    title: TalkifyLocalized.string("settings.subscription_tier"),
                    value: usage.tier.rawValue.capitalized
                )
                ProfileKeyValue(
                    title: TalkifyLocalized.string("settings.total_calls"),
                    value: "\(usage.byModel?.reduce(0) { $0 + $1.callCount } ?? 0)"
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Quick Mode Banner
    
    @ViewBuilder
    private var quickModeBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: TalkifyLocalized.string("settings.fast_mode"))
                    .font(.system(size: 18, weight: .semibold))
                Text(verbatim: TalkifyLocalized.string("settings.fast_mode_desc"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: TalkifyLocalized.string("settings.not_used"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Color.primary.opacity(0.06),
                    in: Capsule()
                )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }
    
    // MARK: - Account
    
    private var accountSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountMetaCard
            dangerZoneCard
        }
        .task {
            if authManager.isRegistered {
                await userManager.refreshProfileIfNeeded(maxAge: 0)
            }
        }
    }

    private var accountMetaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(TalkifyLocalized.string("settings.account_info"))
            settingsCard {
                SettingsValueRow(title: TalkifyLocalized.string("settings.nickname"), description: TalkifyLocalized.string("settings.nickname_desc")) {
                    Text(accountName).foregroundStyle(.secondary)
                }
                SettingsValueRow(title: TalkifyLocalized.string("settings.user_id"), description: TalkifyLocalized.string("settings.user_id_desc")) {
                    HStack(spacing: 8) {
                        Text(userManager.profile?.userId ?? "--")
                            .foregroundStyle(.secondary)
                        if let userID = userManager.profile?.userId {
                            Button {
                                CoreKit.Clipboard.copy(userID)
                                ToastContext.shared.show(TalkifyLocalized.string("settings.copied"))
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(TalkifyLocalized.string("settings.copy_user_id_help"))
                        }
                    }
                }
                SettingsValueRow(title: TalkifyLocalized.string("settings.registration_source"), description: TalkifyLocalized.string("settings.registration_source_desc")) {
                    Text(registerSourceText).foregroundStyle(.secondary)
                }
                SettingsValueRow(title: TalkifyLocalized.string("settings.current_login_method"), description: TalkifyLocalized.string("settings.current_login_method_desc")) {
                    Text(loginMethodsText).foregroundStyle(.secondary)
                }
                SettingsValueRow(title: TalkifyLocalized.string("settings.phone"), description: TalkifyLocalized.string("settings.phone_desc")) {
                    Text(userManager.profile?.phoneMasked ?? TalkifyLocalized.string("settings.not_bound"))
                        .foregroundStyle(.secondary)
                }
                SettingsValueRow(title: TalkifyLocalized.string("settings.apple"), description: TalkifyLocalized.string("settings.phone_desc")) {
                    Text(userManager.profile?.hasApple == true ? TalkifyLocalized.string("settings.apple_bound") : TalkifyLocalized.string("settings.not_bound"))
                        .foregroundStyle(.secondary)
                }
                if let usage = agentManager.usage {
                    SettingsValueRow(title: TalkifyLocalized.string("settings.subscription_tier"), description: TalkifyLocalized.string("settings.subscription_tier_desc")) {
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
                    Task { await container.disconnectGateway() }
                } label: {
                    Label(TalkifyLocalized.string("workspace.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
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
            sectionTitle(TalkifyLocalized.string("settings.danger_zone"))
            settingsCard {
                VStack(alignment: .leading, spacing: 8) {
//                    Label("删除账号", systemImage: "exclamationmark.triangle.fill")
//                        .font(.system(size: 16, weight: .semibold))
//                        .foregroundStyle(.red)
                    Text(TalkifyLocalized.string("settings.delete_account_long_warning"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(TalkifyLocalized.string("settings.sign_out_instead"))
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
                    Label(isDeletingAccount ? TalkifyLocalized.string("settings.deleting") : TalkifyLocalized.string("settings.delete_account"), systemImage: "trash")
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
            Text(TalkifyLocalized.string("settings.usage_view_subscription_hint"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, -38)
                .padding(.bottom, 58)
            
            if let usage = agentManager.usage {
                sectionTitle(TalkifyLocalized.string("settings.current_plan"))
                settingsCard {
                    SettingsValueRow(title: String(format: TalkifyLocalized.string("settings.tier_plan_format"), usage.tier.rawValue.capitalized), description: subscriptionDescription(for: usage)) {
                        Button {
                            if usage.tier == .free {
                                router.presentSheet(.subscription)
                            } else {
                                router.navigate(to: .subscriptionCenter)
                            }
                        } label: {
                            Text(TalkifyLocalized.string("settings.view_plan"))
                                .settingsPickerCapsule()
                        }

                    }
                }
                
                sectionTitle(TalkifyLocalized.string("settings.general_usage_limit"))
                settingsCard {
                    WeeklyQuotaRow(usage: usage.weekly)
                }
                
                if let cycle = usage.cycle {
                    sectionTitle(TalkifyLocalized.string("settings.subscription_cycle"))
                    settingsCard {
                        if let resetsAt = cycle.resetsAt, !resetsAt.isEmpty {
                            SettingsValueRow(title: TalkifyLocalized.string("settings.subscription_cycle_usage"), description: String(format: TalkifyLocalized.string("settings.subscription_cycle_until"), formattedResetDate(resetsAt))) {
                                Text(String(format: TalkifyLocalized.string("settings.cycle_remaining_format"), formatted(max(cycle.unitsLimit - cycle.unitsUsed, 0)), formatted(cycle.unitsLimit)))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            SettingsValueRow(title: TalkifyLocalized.string("settings.cycle_usage_title"), description: "") {
                                Text(String(format: TalkifyLocalized.string("settings.cycle_remaining_format"), formatted(max(cycle.unitsLimit - cycle.unitsUsed, 0)), formatted(cycle.unitsLimit)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if !usage.availableResetCards.isEmpty {
                    sectionTitle(TalkifyLocalized.string("settings.usage_reset"))
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
                            Text(TalkifyLocalized.string("settings.buy_points")).font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 21)
                    }
                }
                
            } else {
                ProgressView(TalkifyLocalized.string("settings.fetching_usage"))
                    .padding(.top, 24)
            }
        }
        .task {
            if authManager.isRegistered {
                agentManager.fetchUsage()
            }
        }
    }
    
    // MARK: - Support & Help

    private var supportSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero card
            supportHeroCard
                .padding(.bottom, 44)

            // Contact section
            sectionTitle(TalkifyLocalized.string("settings.support.contact_section"))
            settingsCard {
                supportLinkRow(
                    icon: "paperplane",
                    iconTint: Color(hex: "2E7CF6"),
                    title: TalkifyLocalized.string("settings.support.contact_email"),
                    subtitle: "code@objc.com"
                ) {
                    openURL(URL(string: "mailto:code@objc.com")!)
                }
                .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }

                supportLinkRow(
                    icon: "bubble.left.and.exclamationmark.bubble.right",
                    iconTint: Color(hex: "0F766E"),
                    title: TalkifyLocalized.string("settings.support.feedback"),
                    subtitle: TalkifyLocalized.string("settings.support.feedback_desc")
                ) {
                    openURL(URL(string: "mailto:code@objc.com")!)
                }
            }

//            sectionTitle(TalkifyLocalized.string("settings.support.help_section"))
//                .padding(.top, 12)
//            settingsCard {
//                supportLinkRow(
//                    icon: "sparkles.rectangle.stack",
//                    iconTint: Color(hex: "8B5CF6"),
//                    title: TalkifyLocalized.string("settings.support.user_guide"),
//                    subtitle: TalkifyLocalized.string("settings.support.user_guide_desc"),
//                    trailingText: TalkifyLocalized.string("settings.coming_soon")
//                ) { }
//                .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }
//
//                supportLinkRow(
//                    icon: "play.rectangle.on.rectangle",
//                    iconTint: Color(hex: "F59E0B"),
//                    title: TalkifyLocalized.string("settings.support.beginner_guide"),
//                    subtitle: TalkifyLocalized.string("settings.support.beginner_guide_desc"),
//                    trailingText: TalkifyLocalized.string("settings.coming_soon")
//                ) { }
//            }
        }
    }

    private var supportHeroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TalkifyLocalized.string("settings.item.support"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text(TalkifyLocalized.string("settings.support.hero_desc"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 52, height: 52)

                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.accentColor)
            }
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: - About

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero card
            aboutHeroCard
                .padding(.bottom, 44)

            // Policy section
            sectionTitle(TalkifyLocalized.string("settings.about.policy_section"))
            settingsCard {
                supportLinkRow(
                    icon: "doc.plaintext",
                    iconTint: Color(hex: "64748B"),
                    title: TalkifyLocalized.string("settings.about.terms_of_service"),
                    subtitle: TalkifyLocalized.string("settings.about.terms_of_service_desc")
                ) {
                    openURL(AgreementURLs.terms)
                }
                .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }

                supportLinkRow(
                    icon: "hand.raised",
                    iconTint: Color(hex: "64748B"),
                    title: TalkifyLocalized.string("settings.about.privacy_policy"),
                    subtitle: TalkifyLocalized.string("settings.about.privacy_policy_desc")
                ) {
                    openURL(AgreementURLs.privacy)
                }
                .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }

                supportLinkRow(
                    icon: "sparkles",
                    iconTint: Color.accentColor,
                    title: TalkifyLocalized.string("settings.about.ai_data_processing"),
                    subtitle: TalkifyLocalized.string("settings.about.ai_data_processing_desc")
                ) {
                    openURL(AgreementURLs.AIData)
                }
                .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }

                supportLinkRow(
                    icon: "exclamationmark.shield",
                    iconTint: Color(hex: "64748B"),
                    title: TalkifyLocalized.string("settings.about.content_policy"),
                    subtitle: TalkifyLocalized.string("settings.about.content_policy_desc")
                ) {
                    openURL(AgreementURLs.content)
                }
                .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }

                supportLinkRow(
                    icon: "function",
                    iconTint: Color(hex: "64748B"),
                    title: TalkifyLocalized.string("settings.about.algorithm_disclosure"),
                    subtitle: TalkifyLocalized.string("settings.about.algorithm_disclosure_desc")
                ) {
                    openURL(AgreementURLs.algorithmDisclosure)
                }
            }

            // Version section
            sectionTitle(TalkifyLocalized.string("settings.about.version_section"))
                .padding(.top, 12)
            settingsCard {
                versionInfoRow(title: TalkifyLocalized.string("settings.about.app_version"), value: shortVersionText)
                    .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }
                versionInfoRow(title: TalkifyLocalized.string("settings.about.build_number"), value: buildVersionText)
                    .overlay(alignment: .bottom) { Divider().padding(.leading, 30) }
                versionInfoRow(title: TalkifyLocalized.string("settings.about.full_version"), value: fullVersionText)
            }
        }
    }

    private var aboutHeroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TalkifyLocalized.string("settings.item.about"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text(TalkifyLocalized.string("settings.about.hero_desc"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 52, height: 52)

                Image(systemName: "info.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.accentColor)
            }
        }
        .padding(18)
        .cardStyle()
    }

    // MARK: - Unavailable

    private var unavailableSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            //            settingsTitle(section.title)
            Text(TalkifyLocalized.string("settings.placeholder_page"))
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
        guard authManager.isRegistered else { return TalkifyLocalized.string("workspace.not_logged_in") }
        return authManager.displayNickname ?? userManager.profile?.nickname ?? "Unknow"
    }
    
    private var accountInitial: String { String(accountName.prefix(1)).uppercased() }
    private var accountSubtitle: String {
        let handle = userManager.profile?.username.isEmpty == false
        ? "@\(userManager.profile!.username)"
            : ""
        let tier = agentManager.usage?.tier.rawValue.capitalized ?? ""
        if handle.isEmpty { return tier.isEmpty ? TalkifyLocalized.string("settings.talkify_user") : tier }
        if tier.isEmpty { return handle }
        return "\(handle) • \(tier)"
    }

    private var registerSourceText: String {
        switch userManager.profile?.registerSource {
        case "phone": return TalkifyLocalized.string("settings.phone_label")
        case "apple": return "Apple"
        case .some(let source) where !source.isEmpty: return source
        default: return "--"
        }
    }

    private var loginMethodsText: String {
        var methods: [String] = []
        if userManager.profile?.hasPhone == true { methods.append(TalkifyLocalized.string("settings.phone_label")) }
        if userManager.profile?.hasApple == true { methods.append("Apple") }
        if methods.isEmpty, let source = userManager.profile?.registerSource, !source.isEmpty {
            methods.append(registerSourceText)
        }
        return methods.isEmpty ? "--" : methods.joined(separator: "、")
    }

    private func deleteAccount() async {
        let keyword = deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.uppercased() == "DELETE" else {
            deleteAccountError = TalkifyLocalized.string("settings.enter_delete_confirm")
            return
        }

        isDeletingAccount = true
        deleteAccountError = nil
        defer { isDeletingAccount = false }

        do {
            try await userManager.deleteAccount()
            showDeleteAccountConfirmation = false
            await container.disconnectGateway()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }
    
    private var weeklyQuotaText: String {
        guard let usage = agentManager.usage else { return TalkifyLocalized.string("settings.unavailable") }
        let remaining = max(usage.weekly.unitsLimit - usage.weekly.unitsUsed, 0)
        return String(format: TalkifyLocalized.string("settings.cycle_remaining_format"), formatted(remaining), formatted(usage.weekly.unitsLimit))
    }
    
    private func subscriptionDescription(for usage: UsageInfo) -> String {
        usage.tier == .free ? TalkifyLocalized.string("settings.free_tier") : TalkifyLocalized.string("settings.subscription_active")
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
    
    private func formattedCN(_ value: Int) -> String {
        if value >= 100_000_000 {
            return String(format: TalkifyLocalized.string("settings.unit.billion"), Double(value) / 100_000_000)
        } else if value >= 10_000 {
            return String(format: TalkifyLocalized.string("settings.unit.ten_thousand"), Double(value) / 10_000)
        } else {
            return "\(value)"
        }
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
            Label(TalkifyLocalized.string("settings.confirm_delete_again"), systemImage: "trash.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.red)

            Text(TalkifyLocalized.string("settings.type_delete_to_confirm"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(TalkifyLocalized.string("settings.enter_delete"), text: $confirmationText)
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
                Button(TalkifyLocalized.string("common.action.cancel"), action: onCancel)
                    .buttonStyle(.bordered)

                Button(role: .destructive, action: onConfirm) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(verbatim: TalkifyLocalized.string("settings.delete_account"))
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
        return .account
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
        .contentShape(Rectangle())
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
                Text(TalkifyLocalized.string("settings.weekly_limit"))
                    .font(.system(size: 17, weight: .semibold))
                if let resetsAt = usage.resetsAt, !resetsAt.isEmpty {
                    Text(String(format: TalkifyLocalized.string("settings.reset_on"), formattedDate(resetsAt)))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                ProgressView(value: min(max(usage.utilizationPct, 0), 100), total: 100)
                    .tint(usage.utilizationPct >= 90 ? .orange : .primary)
                    .frame(width: 132)
                Text(String(format: TalkifyLocalized.string("settings.remaining_pct"), "\(Int(max(100 - usage.utilizationPct, 0).rounded()))%"))
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
            Button(agentManager.isRedeemingResetCard ? "正在使用…" : TalkifyLocalized.string("settings.use_reset_quota")) {
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

// MARK: - Token Activity Tab

private enum TokenActivityTab: Hashable {
    case daily, weekly, cumulative
    var label: String {
        switch self {
        case .daily: return TalkifyLocalized.string("settings.period.daily")
        case .weekly: return TalkifyLocalized.string("settings.period.weekly")
        case .cumulative: return TalkifyLocalized.string("settings.period.cumulative")
        }
    }
}

private struct ProfileStatCell: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Support/About Row Components

private struct SupportLinkRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    let trailingText: String?
    let action: () -> Void

    init(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconTint.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 8)

                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct VersionInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            Spacer(minLength: 24)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
    }
}

// MARK: - Version info helpers

private extension SettingsDetailView {
    var shortVersionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
    }

    var buildVersionText: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--"
    }

    var fullVersionText: String {
        "v\(shortVersionText) (\(buildVersionText))"
    }

    func supportLinkRow(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        SupportLinkRow(
            icon: icon,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle,
            trailingText: trailingText,
            action: action
        )
    }

    func versionInfoRow(title: String, value: String) -> some View {
        VersionInfoRow(title: title, value: value)
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
