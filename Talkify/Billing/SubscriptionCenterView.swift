//
//  SubscriptionCenterView.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/17.
//

import SwiftUI
import CoreKit
import DesignKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SubscriptionCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let navigationActions: SubscriptionCenterNavigationActions
    @StateObject var viewModel: SubscriptionCenterViewModel
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: pageSectionSpacing) {
                heroCard

                if isPadLayout {
                    entitlementComparisonSection
                    subscriptionPlansCard
                } else {
                    currentEntitlementsCard
                    if !viewModel.hasActiveSubscription {
                        subscriptionPlansCard
                        benefitsCard
                    }
                }

                restorePurchaseCard
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isPadLayout ? 24 : 16)
            .padding(.bottom, isPadLayout ? 40 : 28)
            .frame(maxWidth: pageContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color.underPageBackground.ignoresSafeArea())
        .navigationTitle("订阅中心")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        #if os(macOS)
        .frame(maxHeight: 560)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SubscriptionManagementSheet(
                        summaryItems: viewModel.managementSummaryItems,
                        paymentRecords: viewModel.paymentRecords,
                        onManageInStore: {
                            openManageSubscription()
                        }
                    )
        #if os(iOS)
                    .presentationDetents([.large])
        #endif
                } label: {
                    Text(verbatim: TalkifyLocalized.string("billing.subscription.manage"))
                }
//
//                Button("管理") {
//                    viewModel.showManagementSheet = true
//                }
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .overlay {
            if viewModel.isPurchasing {
                purchaseLoadingOverlay
            }
        }
        .sheet(item: $viewModel.purchaseSuccessState) { state in
            PurchaseSuccessSheet(
                state: state,
                onClose: {
                    viewModel.dismissPurchaseSuccess()
                }
            )
#if os(iOS)
            .presentationDetents([.medium])
#endif
        }
        .sheet(isPresented: $viewModel.showManagementSheet) {
            SubscriptionManagementSheet(
                summaryItems: viewModel.managementSummaryItems,
                paymentRecords: viewModel.paymentRecords,
                onManageInStore: {
                    openManageSubscription()
                }
            )
#if os(iOS)
            .presentationDetents([.large])
#endif
        }
        .onChange(of: viewModel.originalTransactionID) { _, _ in
            viewModel.sanitizeOriginalTransactionID()
        }
        .onChange(of: viewModel.errorMessage ?? "") { oldValue, newValue in
            if newValue.isEmpty {
                return
            }
            ToastContext.shared.show(newValue)
            viewModel.errorMessage = nil
        }
        .onChange(of: viewModel.feedbackMessage ?? "") { oldValue, newValue in
            if newValue.isEmpty {
                return
            }
            ToastContext.shared.show(newValue)
            viewModel.feedbackMessage = nil
        }
    }
}

// MARK: - Layout

private extension SubscriptionCenterView {
    var isPadLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    var pageHorizontalPadding: CGFloat {
        isPadLayout ? 28 : 16
    }

    var pageContentMaxWidth: CGFloat {
        isPadLayout ? 1120 : 860
    }

    var pageSectionSpacing: CGFloat {
        isPadLayout ? 20 : 18
    }
}

// MARK: - Hero

private extension SubscriptionCenterView {
    var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                heroIntro

                Spacer()

                heroIcon
            }

            heroMetricsGroup
        }
        .padding(isPadLayout ? 24 : 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: viewModel.hasActiveSubscription
                        ? [
                            Color(hex: "081B2A"),
                            Color(hex: "0F3B58"),
                            Color(hex: "0F766E")
                        ]
                        : [
                            Color(hex: "1C1B4B"),
                            Color(hex: "234B9A"),
                            Color(hex: "0F766E")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    var heroIntro: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.heroTitle)
                    .font(.system(size: isPadLayout ? 28 : 26, weight: .bold))
                    .foregroundColor(.white)

                Text(viewModel.heroSubtitle)
                    .font(.system(size: isPadLayout ? 15 : 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: isPadLayout ? 520 : .infinity, alignment: .leading)

            if isPadLayout {
                heroIcon
            }
        }
    }

    var heroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: 56, height: 56)

            Image(systemName: viewModel.hasActiveSubscription ? "crown.fill" : "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    var heroMetricsGroup: some View {
        HStack(spacing: 12) {
            heroMetricChip(title: "当前订阅", value: viewModel.currentSubscriptionName)

            Button {
                navigationActions.showPointsCenter()
            } label: {
                heroMetricChip(title: "可用点数", value: viewModel.currentPointsText, trailingIcon: "arrow.up.right")
            }
            .buttonStyle(.plain)

            heroMetricChip(title: "状态", value: viewModel.currentStatusBadgeText)
        }
    }

    func heroMetricChip(title: String, value: String, trailingIcon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                }
            }

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    var purchaseSelectedSubscriptionButton: some View {
        Button {
            guard let product = viewModel.selectedSubscriptionProduct else { return }
#if canImport(StoreKit)
            Task {
                await viewModel.purchase(product: product)
            }
#endif
        } label: {
            HStack(spacing: 8) {
                if viewModel.isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(viewModel.heroPrimaryButtonTitle)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(viewModel.canPurchaseSelectedSubscription ? Color.accentColor : Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPurchaseSelectedSubscription)
    }
}

// MARK: - Plans

private extension SubscriptionCenterView {
    var subscriptionPlansCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: viewModel.hasActiveSubscription ? "订阅管理" : "选择你的会员方案",
                subtitle: viewModel.hasActiveSubscription
                    ? "你当前已开通会员，如需切换或取消套餐，请前往 Apple 订阅管理"
                    : "请选择最适合你的 Talkify Plus 方案"
            )

            if viewModel.subscriptionProducts.isEmpty && viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if viewModel.subscriptionProducts.isEmpty {
                activeSubscriptionManagementHint
            } else if isPadLayout {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(viewModel.subscriptionProducts) { product in
                        subscriptionPlanCard(product)
                    }
                }

                purchaseSelectedSubscriptionButton
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.subscriptionProducts) { product in
                            subscriptionPlanCard(product)
                                .frame(width: subscriptionCardWidth)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }

                purchaseSelectedSubscriptionButton
            }
        }
        .padding(20)
        .surfaceCard()
        .id("plans")
    }

    var activeSubscriptionManagementHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: viewModel.hasActiveSubscription ? "checkmark.seal.fill" : "cart.badge.questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(viewModel.hasActiveSubscription ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.hasActiveSubscription ? "当前订阅已生效" : "当前暂未获取到可订阅商品")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text(viewModel.hasActiveSubscription ? "为避免重复购买或误切换套餐，App 内不再展示其它自动续订商品。你可以在 App Store 订阅管理中变更或取消套餐。" : "请稍后重试，或检查网络连接。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.controlBackground)
        )
    }

    func subscriptionPlanCard(_ product: BillingProduct) -> some View {
        let selected = viewModel.isSelectedSubscription(product)
        let recommended = viewModel.isRecommendedSubscription(product)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                viewModel.selectSubscriptionProduct(product)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        Text(viewModel.productSubtitle(product))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    if recommended {
                        Text(verbatim: TalkifyLocalized.string("billing.subscription.recommended"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "FF8A00"))
                            )
                    }
                }

//                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected ? Color.accentColor : .secondary)

                    Text(selected ? "当前已选择" : "点击选择")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selected ? Color.accentColor : .secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: isPadLayout ? 112 : 80, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        selected ? Color.accentColor : Color.black.opacity(0.05),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Benefits

private extension SubscriptionCenterView {
    var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: viewModel.hasActiveSubscription ? "你当前选择方案的权益" : "方案权益",
                subtitle: viewModel.selectedSubscriptionProduct?.displayName ?? "请选择会员方案"
            )

            if viewModel.selectedBenefitLines().isEmpty {
                Text(verbatim: TalkifyLocalized.string("billing.subscription.no_benefits"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.selectedBenefitLines()) { line in
                        benefitRow(line)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.systemBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    func benefitRow(_ line: SubscriptionCenterViewModel.SubscriptionBenefitLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 36, height: 36)

                Image(systemName: line.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                if let detail = line.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Current Entitlements

private extension SubscriptionCenterView {
    var entitlementComparisonSection: some View {
        HStack(alignment: .top, spacing: 16) {
            currentEntitlementsCard
                .frame(maxWidth: .infinity, alignment: .top)
            if !viewModel.hasActiveSubscription{
                benefitsCard
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    var currentEntitlementsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "当前账号权益",
                subtitle: "这是当前账号已经生效的会员能力"
            )

            if viewModel.currentEntitlementSummary().isEmpty {
                Text(verbatim: TalkifyLocalized.string("billing.subscription.no_entitlements"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.currentEntitlementSummary()) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(row.value)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(20)
        .surfaceCard()
    }
}

// MARK: - Restore

private extension SubscriptionCenterView {
    var restorePurchaseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "恢复购买",
                subtitle: "用于同步 App Store 已有订阅并刷新当前账号权益"
            )

//            Text("系统会优先尝试通过 App Store 同步并自动验单；若当前设备没有找到可恢复交易")
//                .font(.system(size: 13))
//                .foregroundColor(.secondary)
//                .fixedSize(horizontal: false, vertical: true)
//
//            TextField("请输入 original_transaction_id（可选）", text: $viewModel.originalTransactionID)
//                .textFieldStyle(.plain)
//                .padding(.horizontal, 16)
//                .frame(height: 52)
//                .background(
//                    RoundedRectangle(cornerRadius: 16, style: .continuous)
//                        .fill(Color.controlBackground)
//                )

            if let restoreErrorMessage = viewModel.restoreErrorMessage, !restoreErrorMessage.isEmpty {
                Text(restoreErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "D35454"))
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        await viewModel.restorePurchase()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isRestoring {
                            ProgressView()
                        }

                        Text(viewModel.isRestoring ? "恢复中..." : "恢复购买")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canRestore)
                Spacer()
            }
        }
        .padding(20)
        .surfaceCard()
    }
}

// MARK: - Common

private extension SubscriptionCenterView {
    func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var purchaseLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text(viewModel.purchasingTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                Text(viewModel.purchasingMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.systemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .padding(24)
        }
    }

    func openManageSubscription() {
#if os(iOS)
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
#elseif os(macOS)
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        NSWorkspace.shared.open(url)
#endif
    }
    
    var subscriptionCardWidth: CGFloat {
    #if os(macOS)
        210
    #else
        196
    #endif
    }
}

// MARK: - Management Sheet

private struct SubscriptionManagementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let summaryItems: [SubscriptionCenterViewModel.SubscriptionManagementItem]
    let paymentRecords: [SubscriptionCenterViewModel.PaymentRecordItem]
    let onManageInStore: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                summaryCard
                paymentRecordsCard
                manageActionCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.underPageBackground)
        .navigationTitle("订阅管理")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: TalkifyLocalized.string("billing.subscription.current"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            ForEach(summaryItems) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(item.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(item.value ?? "--")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .surfaceCard()
    }

    var paymentRecordsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: TalkifyLocalized.string("billing.subscription.payment_history"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            if paymentRecords.isEmpty {
                Text(verbatim: TalkifyLocalized.string("billing.subscription.no_payment_history"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 12) {
                    ForEach(paymentRecords) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)

                                Text(item.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(item.amountText)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)

                                Text(item.statusText)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(20)
        .surfaceCard()
    }

    var manageActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: TalkifyLocalized.string("billing.subscription.system_management"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Text(verbatim: TalkifyLocalized.string("billing.subscription.system_management_desc"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onManageInStore) {
                Text(verbatim: TalkifyLocalized.string("billing.subscription.go_to_system"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .surfaceCard()
    }
}

// MARK: - Success Sheet

private struct PurchaseSuccessSheet: View {
    let state: SubscriptionCenterViewModel.PurchaseSuccessState
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: state.productType == "subscription" ? "crown.fill" : "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Color(hex: "FF8A00"))

            VStack(spacing: 8) {
                Text(state.productType == "subscription" ? "订阅开通成功" : "购买成功")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text(state.productName)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                resultRow(title: "当前余额", value: "\(state.availablePoints.cleanDisplay) 点")
                resultRow(title: "订阅状态", value: state.subscriptionActive ? "已生效" : "未生效")

                if !state.productName.isEmpty {
                    resultRow(title: "当前订阅", value: state.productName)
                }

                if let originalTransactionID = state.originalTransactionID, !originalTransactionID.isEmpty {
                    resultRow(title: "原始交易号", value: originalTransactionID)
                }
            }

            Button(action: onClose) {
                Text(verbatim: TalkifyLocalized.string("billing.points.got_it"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color.systemBackground)
    }

    func resultRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Surface

extension View {
    func surfaceCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.systemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
    }
}
