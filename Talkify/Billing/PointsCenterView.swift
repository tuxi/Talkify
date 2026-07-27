//
//  PointsCenterView.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/17.
//

import SwiftUI
import CoreKit
#if os(iOS)
import UIKit
#endif
import DesignKit

struct PointsCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject var viewModel: PointsCenterViewModel
    
    @State private var openURL: URL?
    @State private var showPaidServiceAgreement = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    headerCard
                    pointsPurchaseSection
                    pointsValidityNote
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 190)
                .frame(maxWidth: pageContentMaxWidth)
                .frame(maxWidth: .infinity)
            }

            bottomPurchaseBar
        }
        .navigationTitle(TalkifyLocalized.string("billing.points_center"))
        .toolbar {
            NavigationLink {
                PointsLedgerView(
                    viewModel: PointsLedgerViewModel(
                        billingService: viewModel.billingService
                    )
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(verbatim: TalkifyLocalized.string("billing.points.ledger"))
                }
                .font(.system(size: 13, weight: .semibold))
            }
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
#endif
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(item: $viewModel.purchaseSuccessState) { state in
            PointsPurchaseSuccessSheet(
                state: state,
                onClose: {
                    viewModel.dismissPurchaseSuccess()
                }
            )
#if os(iOS)
            .presentationDetents([.height(328)])
            .presentationDragIndicator(.visible)
#endif
        }
        .sheet(isPresented: $showPaidServiceAgreement) {
            PaidServiceAgreementSheet(
                title: TalkifyLocalized.string("billing.paid_service_agreement"),
                content: TalkifyLocalized.string("billing.paid_agreement_content"),
                onAgree: {
                    showPaidServiceAgreement = false
                    Task {
                        await viewModel.purchaseSelectedPointPack()
                    }
                },
                onCancel: {
                    showPaidServiceAgreement = false
                },
                openURL: { url in
                    showPaidServiceAgreement = false
                    DispatchQueue.main.async {
                        if url.host() == "paid-protocol" {
                            openURL = AgreementURLs.paid
                        }
                    }
                }
            )
#if os(iOS)
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
#endif
        }
        .sheet(item: $openURL, content: { url in
            NavigationStack {
                BrowserView(url: url)
            }
        })
        .onChange(of: viewModel.originalTransactionID) { _, _ in
            viewModel.sanitizeOriginalTransactionID()
        }
        .onChange(of: viewModel.errorMessage ?? "") { _, newValue in
            guard !newValue.isEmpty else { return }
            ToastContext.shared.show(newValue)
        }
        .onChange(of: viewModel.feedbackMessage ?? "") { _, newValue in
            guard !newValue.isEmpty else { return }
            ToastContext.shared.show(newValue)
        }
    }
}

// MARK: - Background

private extension PointsCenterView {
    var pageHorizontalPadding: CGFloat {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 28 : 18
#else
        24
#endif
    }

    var pageContentMaxWidth: CGFloat {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 700 : 560
#else
        700
#endif
    }

    var pageBackground: some View {
        Color(hex: colorScheme == .dark ? "080A09" : "F3F7FB")
    }
}

// MARK: - Check-In

private extension PointsCenterView {
    var checkInCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.checkInCardTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    Text(viewModel.checkInCardSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(checkInIconBackground)
                        .frame(width: 46, height: 46)

                    Image(systemName: viewModel.hasCheckedInToday ? "checkmark.seal.fill" : "gift.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(checkInAccentColor)
                }
            }

            HStack(spacing: 12) {
                checkInMetricChip(
                    title: TalkifyLocalized.string("billing.today_reward"),
                    value: "\(viewModel.checkInRewardText) 点",
                    icon: "sparkles"
                )
                checkInMetricChip(
                    title: TalkifyLocalized.string("billing.server_date"),
                    value: viewModel.checkInDateText,
                    icon: "calendar"
                )
                checkInMetricChip(
                    title: TalkifyLocalized.string("billing.current_points"),
                    value: viewModel.checkInAvailablePointsText,
                    icon: "bolt.fill"
                )
            }

            Button {
                Task {
                    await viewModel.performCheckIn()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isCheckingIn {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: viewModel.hasCheckedInToday ? "checkmark.circle.fill" : "hands.sparkles.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Text(viewModel.checkInButtonTitle)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            viewModel.hasCheckedInToday
                            ? AnyShapeStyle(Color.secondary.opacity(0.28))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "F59E0B"), Color(hex: "F97316")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.hasCheckedInToday || viewModel.isCheckingIn || viewModel.checkInStatus == nil)
        }
        .padding(20)
        .dreamSurfaceCard(colorScheme: colorScheme)
    }

    func checkInMetricChip(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(checkInAccentColor)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.controlBackground)
        )
    }

    var checkInAccentColor: Color {
        colorScheme == .dark ? Color(hex: "FBBF24") : Color(hex: "D97706")
    }

    var checkInIconBackground: Color {
        checkInAccentColor.opacity(colorScheme == .dark ? 0.18 : 0.14)
    }
}


// MARK: - Header Card

private extension PointsCenterView {
    var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(headerCardBackground)

            headerCardArt

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundColor(pointsAccent)

                    Text(viewModel.availablePointsText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(headerPrimaryText)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 46)
                .padding(.bottom, 44)

                HStack(spacing: 0) {
                    walletMetricBlock(title: TalkifyLocalized.string("billing.frozen_points"), value: viewModel.frozenPointsText)
                    headerDivider
                    walletMetricBlock(title: TalkifyLocalized.string("billing.discount_coefficient"), value: viewModel.pointDiscountText)
                    headerDivider
                    walletMetricBlock(title: TalkifyLocalized.string("billing.subscription_status"), value: viewModel.currentSubscriptionText)

                }
                .padding(.vertical, 22)
                .background(headerMetricBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(headerStroke, lineWidth: 1)
        )
    }

    var headerCardBackground: Color {
        colorScheme == .dark ? Color(hex: "1D2021") : Color(hex: "19252B")
    }

    var headerMetricBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.26)
    }

    var headerPrimaryText: Color {
        .white
    }

    var headerSecondaryText: Color {
        Color.white.opacity(0.72)
    }

    var headerStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

    var pointsAccent: Color {
        Color(hex: "4ADE80")
    }

    var headerDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.26))
            .frame(width: 1, height: 32)
    }

    var headerCardArt: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Path { path in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    path.move(to: CGPoint(x: w * 0.82, y: h * 0.16))
                    path.addCurve(
                        to: CGPoint(x: w * 0.78, y: h * 0.64),
                        control1: CGPoint(x: w * 0.95, y: h * 0.36),
                        control2: CGPoint(x: w * 0.70, y: h * 0.36)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.95, y: h * 0.48),
                        control1: CGPoint(x: w * 0.86, y: h * 0.58),
                        control2: CGPoint(x: w * 0.90, y: h * 0.66)
                    )
                }
                .stroke(pointsAccent.opacity(0.28), lineWidth: 2.2)

                Image(systemName: "sparkle")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundColor(pointsAccent.opacity(0.22))
                    .offset(x: -68, y: 22)
            }
        }
        .allowsHitTesting(false)
    }

    func walletMetricBlock(title: String, value: String) -> some View {
        VStack(spacing: 7) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(headerPrimaryText)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(headerSecondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: - Purchase Section

private extension PointsCenterView {
    var pointsPurchaseSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: TalkifyLocalized.string("billing.select_points"),
                subtitle: viewModel.hasPurchasableProducts
                    ? ""
                    : TalkifyLocalized.string("billing.unavailable_in_region")
            )

            if viewModel.isLoading && viewModel.pointPackProducts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else if viewModel.pointPackProducts.isEmpty {
                unavailableStateCard
            } else {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(viewModel.pointPackProducts) { product in
                        pointPackCard(product)
                    }
                }
            }
        }
    }
    
    var pointsValidityNote: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(validityIconColor)

            (
                Text(verbatim: TalkifyLocalized.string("billing.points.validity"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(validityTextColor)
                +
                Text(viewModel.validityText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(pointsAccent)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    var unavailableStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Color.accentColor.opacity(0.82))

            Text(verbatim: TalkifyLocalized.string("billing.points.unavailable"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(verbatim: TalkifyLocalized.string("billing.points.unavailable_hint"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.controlBackground)
        )
    }

    func pointPackCard(_ product: BillingProduct) -> some View {
        let isSelected = viewModel.selectedPointPackProduct?.productCode == product.productCode

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                viewModel.selectPointPack(product)
            }
        } label: {
            VStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(pointsAccent)

                    Text("\(product.pointAmount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(packPrimaryTextColor(isSelected: isSelected))
                        .minimumScaleFactor(0.78)
                        .lineLimit(1)
                }

                Text(viewModel.productPriceText(product))
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(packSecondaryTextColor(isSelected: isSelected))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: pointPackCardHeight)
            .background(cardBackground(isSelected: isSelected))
            .overlay(cardOverlay(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    var pointPackCardHeight: CGFloat {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 128 : 112
#else
        128
#endif
    }

    var validityIconColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color(hex: "6B7280")
    }

    var validityTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color(hex: "4B5563")
    }

    func packPrimaryTextColor(isSelected: Bool) -> Color {
         isSelected ? Color.white : (colorScheme == .dark ? Color.white : Color(hex: "101827"))
    }

    func packSecondaryTextColor(isSelected: Bool) -> Color {
        isSelected ? Color.white.opacity(0.74) : (colorScheme == .dark ? Color.white.opacity(0.62) : Color(hex: "6B7280"))
    }

    func cardBackground(isSelected: Bool) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                pointsAccent.opacity(colorScheme == .dark ? 0.16 : 0.18)
            )
        } else {
            return AnyShapeStyle(
                colorScheme == .dark
                ? Color(hex: "181A1A")
                : Color.white.opacity(0.9)
            )
        }
    }

    @ViewBuilder
    func cardOverlay(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                isSelected
                ? pointsAccent.opacity(colorScheme == .dark ? 0.82 : 0.9)
                : (colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.035)),
                lineWidth: isSelected ? 1.4 : 1
            )
    }
}

// MARK: - Bottom Purchase Bar

private extension PointsCenterView {
    var bottomPurchaseBar: some View {
        VStack(spacing: 14) {
            Button {
                guard viewModel.selectedPointPackProduct != nil else { return }
                if !viewModel.isAgreement {
                    showPaidServiceAgreement = true
                    return
                }
#if canImport(StoreKit)
                    Task {
                        await viewModel.purchaseSelectedPointPack()
                    }
#endif
            } label: {
                HStack(spacing: 8) {
                    if let selected = viewModel.selectedPointPackProduct,
                       viewModel.isPurchasing(selected) {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(viewModel.primaryPurchaseButtonTitle)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundColor(Color(hex: "061108"))
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "22C55E"), Color(hex: "A3FF2F")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .opacity(viewModel.selectedPointPackProduct == nil ? 0.55 : 1)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedPointPackProduct == nil)
            
            AgreementRow(isAgreed: $viewModel.isAgreement, content: TalkifyLocalized.string("billing.payment_agreement"), openURL: { url in
                if url.host() == "paid-protocol" {
                    openURL = AgreementURLs.paid
                }
            })
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 22)
        .padding(.bottom, bottomBarBottomPadding)
        .frame(maxWidth: pageContentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    pageBottomFadeColor.opacity(0),
                    pageBottomFadeColor.opacity(0.92),
                    pageBottomFadeColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    var bottomBarBottomPadding: CGFloat {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 30 : 28
#else
        30
#endif
    }

    var pageBottomFadeColor: Color {
        colorScheme == .dark ? Color(hex: "080A09") : Color(hex: "F3F7FB")
    }

    var agreementTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color(hex: "6B7280")
    }

    var agreementLinkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color(hex: "374151")
    }
}

// MARK: - Restore

private extension PointsCenterView {
    var restorePurchaseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: TalkifyLocalized.string("billing.sync_purchase_records"),
                subtitle: "用于补发尚未入账的 App Store 交易；消耗型点数包不能像订阅一样恢复"
            )

            TextField("请输入 original_transaction_id（可选）", text: $viewModel.originalTransactionID)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.controlBackground)
                )

            if let restoreErrorMessage = viewModel.restoreErrorMessage, !restoreErrorMessage.isEmpty {
                Text(restoreErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "D35454"))
            }

            Button {
                Task {
                    await viewModel.restorePurchase()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRestoring {
                        ProgressView()
                    }

                    Text(viewModel.restoreButtonTitle)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            viewModel.canRestore
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "0F766E"), Color(hex: "2563EB")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.secondary.opacity(0.3))
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRestore)
        }
        .padding(.top, 8)
    }
}

// MARK: - Section Header

private extension PointsCenterView {
    func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Surface Card

private extension View {
    func dreamSurfaceCard(colorScheme: ColorScheme) -> some View {
        background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    colorScheme == .dark
                    ? Color.white.opacity(0.04)
                    : Color.systemBackground
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    colorScheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.04),
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark
            ? Color.black.opacity(0.18)
            : Color(hex: "9FB4C8").opacity(0.10),
            radius: 16,
            x: 0,
            y: 8
        )
    }
}

// MARK: - Success Sheet

private struct PointsPurchaseSuccessSheet: View {
    let state: PointsCenterViewModel.PurchaseSuccessState
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Color(hex: "FF8A00"))

            VStack(spacing: 8) {
                Text(verbatim: TalkifyLocalized.string("billing.points.purchase_success"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text(state.productName)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                resultRow(title: "当前余额", value: "\(state.availablePoints.cleanDisplay) 点")

                if let currentSubscription = state.currentSubscription, !currentSubscription.isEmpty {
                    resultRow(title: "当前订阅", value: currentSubscription)
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
