//
//  SubscriptionView.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/16.
//

import SwiftUI
import CoreKit
import AgentKit
import DesignKit
#if os(iOS)
import UIKit
#endif

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    let container: AppContainer
    @State private var router = SubscriptionRouter()
    @StateObject var viewModel: SubscriptionViewModel
    
    @State private var isContentPresented = false
    @State private var isHeroAnimationEnabled = false
    @State private var showPaidServiceAgreement = false
    
    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .toolbar(content: {
                    ToolbarItem(placement: leadingToolbarPlacement) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(topBarForeground)
                        }
                    }
                    
                    ToolbarItem(placement: toolbarActionPlacement) {
                        
                         footerLinkButton(title: viewModel.restoreButtonTitle) {
                             Task {
                                 await viewModel.restorePurchase()
                             }
                         }
                         .disabled(viewModel.isRestoring)

                    }
                })
            

#if os(macOS)
                .frame(minHeight: 580) // 确保 macOS 下有一个合理的展示窗口
#endif
                .withSubscriptionNavigationDestinations(container: container, router: router)
                .onChange(of: viewModel.errorMessage ?? "") { oldValue, newValue in
                    if newValue.isEmpty {
                        return
                    }
                    ToastContext.shared.show(newValue)
                }
                .onChange(of: viewModel.feedbackMessage ?? "") { oldValue, newValue in
                    if newValue.isEmpty {
                        return
                    }
                    ToastContext.shared.show(newValue)
                }
                .sheet(isPresented: $showPaidServiceAgreement) {
                    PaidServiceAgreementSheet(
                        title: "付费服务协议",
                        content: "为保障您的合法权益，请同意[《Talkify 付费服务协议》（含自动续费条款）](dreamai://vip-protocol)",
                        onAgree: {
                            showPaidServiceAgreement = false
                            Task {
                                await viewModel.continuePurchase()
                            }
                        },
                        onCancel: {
                            showPaidServiceAgreement = false
                        },
                        openURL: { url in
                            showPaidServiceAgreement = false
                            if url.host() == "vip-protocol" {
                                router.navigate(to: .openURL(AgreementURLs.paid))
                            }
                        }
                    )
        #if os(iOS)
                    .presentationDetents([.height(250)])
                    .presentationDragIndicator(.visible)
        #endif
                }
        }
        .withAppCoverDestinations(coverDestinations: $router.presentedCover, container: container)
        .withAppSheetDestinations(sheetDestinations: $router.presentedSheet, container: container)
        .injectSubscriptionContext(container: container, router: router)
        
    }
    
    @ViewBuilder
    private func content(proxy: GeometryProxy, isIpad: Bool) -> some View {
        let heroHeight = heroHeight(proxy: proxy)
        let safeBottom = proxy.safeAreaInsets.bottom
        if isIpad {
            padPaywallContent(proxy: proxy, safeBottom: safeBottom)
        } else {        
            phonePaywallContent(proxy: proxy, heroHeight: heroHeight, safeBottom: safeBottom)
        }
    }
    
    private func phonePaywallContent(proxy: GeometryProxy, heroHeight: CGFloat, safeBottom: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // 底层大背景渐变
            pageBackground.ignoresSafeArea()
            subscriptionHeroImageBackground(height: heroHeight)
                .ignoresSafeArea(edges: .top)
            
            // 视觉桥接层：现在它知道动画在哪结束了
            backgroundBridge(heroHeight: heroHeight)
            
            // 沉浸式内容容器 (不再使用卡片效果，直接平铺)
            contentOverlay(proxy: proxy, safeBottom: safeBottom)
                .opacity(isContentPresented ? 1 : 0.01)
                .offset(y: isContentPresented ? 0 : 72)
                .scaleEffect(isContentPresented ? 1 : 0.985, anchor: .bottom)
                .animation(.spring(response: 0.62, dampingFraction: 0.86), value: isContentPresented)
        }
    }
    
    private var content: some View {
        GeometryReader { proxy in
#if os(macOS)
            content(proxy: proxy, isIpad: true)
#else
            content(proxy: proxy, isIpad: DeviceInfo.isPadLayout)
#endif
        }
        .task {
            await Task.yield()
            
            async let loadTask: Void = viewModel.load()
            
            if !isHeroAnimationEnabled {
                try? await Task.sleep(for: .milliseconds(80))
                isHeroAnimationEnabled = true
            }
            
            _ = await loadTask
            
            if !isContentPresented {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
                    isContentPresented = true
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $viewModel.showPlanComparison, content: {
            SubscriptionPlanComparisonView(
                title: viewModel.titleText,
                products: viewModel.subscriptionProducts,
                rows: viewModel.comparisonRows,
                priceTextProvider: { product in
                    viewModel.productPriceText(product)
                }
            )
        })
        #else
        .sheet(isPresented: $viewModel.showPlanComparison, content: {
            SubscriptionPlanComparisonView(
                title: viewModel.titleText,
                products: viewModel.subscriptionProducts,
                rows: viewModel.comparisonRows,
                priceTextProvider: { product in
                    viewModel.productPriceText(product)
                }
            )
        })
        #endif
        .sheet(item: $viewModel.purchaseSuccessState) { state in
            SubscriptionPurchaseSuccessSheet(
                state: state,
                onClose: {
                    viewModel.purchaseSuccessState = nil
                    dismiss()
                }
            )
#if os(iOS)
            .presentationDetents([.medium])
#endif
        }
    }
    
    private func contentOverlay(proxy: GeometryProxy, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(minHeight: 40)
            if viewModel.isLoading && viewModel.subscriptionProducts.isEmpty {
                loadingContent(safeBottom: safeBottom)
            } else {
                VStack(spacing: 0) {
                    headerArea
                        .padding(.bottom, 30)
                    
                    bottomArea(safeBottom: safeBottom)
                }
                .opacity(isContentPresented ? 1 : 0.01)
                .offset(y: isContentPresented ? 0 : 72)
                .scaleEffect(isContentPresented ? 1 : 0.985, anchor: .bottom)
                .animation(.spring(response: 0.62, dampingFraction: 0.86), value: isContentPresented)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
    }
    
    private func backgroundBridge(heroHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 80)
                .mask {
                    LinearGradient(colors: [.clear, .black, .clear], startPoint: .top, endPoint: .bottom)
                }
                .offset(y: heroHeight - 40)
            // 1. 顶部雾化层：提前在动画区域内进行色彩预铺，消除硬切线
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: bottomSurfaceFill.opacity(0.3), location: 0.4),
                    .init(color: bottomSurfaceFill.opacity(0.8), location: 0.8),
                    .init(color: bottomSurfaceFill, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160) // 增大过渡区间
            .offset(y: heroHeight - 120) // 向上大幅度偏移，让过渡在动画区域内就开始
            
            // 2. 纯色承载层：起始位置往下压一点，确保它的“硬顶边缘”被上面的渐变完全覆盖
            VStack(spacing: 0) {
                Color.clear.frame(height: heroHeight + 30)
                bottomSurfaceFill
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false) // 保证背景层不干扰内容点击
    }
    
    // 修改 bottomSurfaceFill
    var bottomSurfaceFill: Color {
        colorScheme == .dark
        ? Color(hex: "07151C") // 纯色更利于固定感
        : Color(hex: "F7FAFC")
    }
}

// MARK: - 沉浸式背景组件

private extension SubscriptionView {
    var immersiveBottomSurface: some View {
        ZStack(alignment: .top) {
            // 主体背景色
            bottomSurfaceFill
            
            // 顶部边缘的“向上提”的模糊效果
            // 压在动画上面，形成整体感
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 120) // 模糊过渡区高度
                .offset(y: -100)    // 向上提，压在动画上
        }
        .ignoresSafeArea(edges: .bottom)
    }
    var toolbarActionPlacement: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .topBarTrailing
#endif
    }
    
    var leadingToolbarPlacement: ToolbarItemPlacement {
#if os(macOS)
        .cancellationAction
#else
        .topBarLeading
#endif
    }
}

// MARK: - iPad Centered Paywall

private extension SubscriptionView {
    func padPaywallContent(proxy: GeometryProxy, safeBottom: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                padHeroHeader
                padSheetBody(safeBottom: safeBottom)
            }
            .frame(maxWidth: 580)
        }
        .ignoresSafeArea(.all)
    }
    
    var padHeroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Image("SubscriptionHeroBackground")
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
            
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.10), location: 0.0),
                            .init(color: .black.opacity(0.18), location: 0.44),
                            .init(color: padHeroBottomOverlay, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.titleText)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: "7CF7D4"),
                                Color(hex: "69A7FF"),
                                Color(hex: "A875FF")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing,
                        )
                    )
                
                Text(viewModel.subtitleText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
        .frame(height: 180)
    }
    
    func padSheetBody(safeBottom: CGFloat) -> some View {
        VStack(spacing: 22) {
            if viewModel.isLoading && viewModel.subscriptionProducts.isEmpty {
                loadingHeaderArea
                    .padding(.vertical, 34)
                    .skeletonShimmer(active: true)
            } else {
                padBenefitGrid
                padProductSection
                
                Text(viewModel.renewHintText)
                    .font(.system(size: 13))
                    .foregroundColor(bottomHintColor)
                    .padding(.top, -4)
                
                bottomActionSection
                footerSection
                    .padding(.bottom, safeBottom > 0 ? 0 : 10)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }
    
    var padBenefitGrid: some View {
        ScrollView(.horizontal) {
            LazyHGrid(
                rows: [
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(viewModel.benefitLines(for: viewModel.selectedProduct).prefix(6)) { line in
                    PadBenefitFeatureCard(line: line, colorScheme: colorScheme)
                }
            }
        }
    }
    
    var padProductSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("选择会员方案")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(heroTitleColor)
                
                Spacer()
                
//                Button {
//                    viewModel.showPlanComparison = true
//                } label: {
//                    Text("权益详情")
//                        .font(.system(size: 13, weight: .semibold))
//                        .foregroundColor(Color.accentColor)
//                }
//                .buttonStyle(.plain)
            }
            
            ScrollView(.horizontal) {
                LazyHGrid(
                    rows: [
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(viewModel.subscriptionProducts) { product in
                        PadSubscriptionProductCard(
                            product: product,
                            isSelected: viewModel.isSelected(product),
                            isRecommended: viewModel.isRecommended(product),
                            priceText: viewModel.productPriceText(product),
                            periodText: viewModel.productPeriodText(product),
                            pointGiftText: viewModel.productPointGiftText(product),
                            colorScheme: colorScheme
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.90)) {
                                viewModel.selectProduct(product)
                            }
                        }
                    }
                }
            }
        }
    }
    
    var padPageBackground: Color {
        colorScheme == .dark ? Color(hex: "02080C") : Color(hex: "F3F7FB")
    }
    
    var padSheetBackground: Color {
        colorScheme == .dark ? Color(hex: "061217") : Color(hex: "F8FBFD")
    }
    
    var padSheetStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    var padHeroBottomOverlay: Color {
        colorScheme == .dark ? Color(hex: "061217").opacity(0.98) : Color(hex: "07181D").opacity(0.82)
    }
}

// MARK: - 权益列表 (局部滚动)

private extension SubscriptionView {
    var headerArea: some View {
        VStack(spacing: 20) {
            // 标题
            VStack(spacing: 8) {
                Text(viewModel.titleText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: "4ADE80"), // 翠绿 (Emerald)
                                Color(hex: "3B82F6"), // 宝蓝 (Blue)
                                Color(hex: "A855F7")  // 紫色 (Purple)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                HStack {
                    Text(viewModel.subtitleText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(heroSubtitleColor)
                        .multilineTextAlignment(.center)
                    
//                    NavigationLink {
//                        SubscriptionPlanComparisonView(
//                            title: viewModel.titleText,
//                            products: viewModel.subscriptionProducts,
//                            rows: viewModel.comparisonRows,
//                            priceTextProvider: { product in
//                                viewModel.productPriceText(product)
//                            }
//                        )
//                    } label: {
//                        Text("详情 >")
//                            .font(.system(size: 9, weight: .medium))
//                            .foregroundColor(.white.opacity(0.86))
//                            .padding(.horizontal, 4)
//                            .padding(.vertical, 2)
//                            .background(
//                                LinearGradient(
//                                    colors: [
//                                        Color(hex: "3B82F6"), // 宝蓝 (Blue)
//                                        Color(hex: "A855F7"),  // 紫色 (Purple)
////                                        Color(hex: "4ADE80"), // 翠绿 (Emerald)
//                                    ],
//                                    startPoint: .leading,
//                                    endPoint: .trailing
//                                )
//                            )
//                            .clipShape(RoundedRectangle(cornerRadius: 5))
//                    }

                }
            }
            
            Spacer()
            
            // 权益列表：支持上下滚动，最大8行
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(viewModel.benefitLines(for: viewModel.selectedProduct).prefix(8)) { line in
                        benefitRow(line)
                    }
                }
                .padding(.vertical, 8)
            }
            // 限制高度：15(字体)+12(间距)+detail高度，预估一行44左右
            .frame(height: CGFloat(min(viewModel.benefitLines(for: viewModel.selectedProduct).count, 8)) * 46)
            .padding(.horizontal, 24)
            // 列表顶部和底部做渐变淡出，增强沉浸感
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
    
    func benefitRow(_ line: SubscriptionViewModel.SubscriptionBenefitLine) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: line.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(heroBulletColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.system(size: 16, weight: .semibold)) // 文字稍微大一点
                    .foregroundColor(heroTitleColor)
                
                if let detail = line.detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(heroSubtitleColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 底部操作区

private extension SubscriptionView {
    func bottomArea(safeBottom: CGFloat) -> some View {
        VStack(spacing: 16) {
            // 1. 商品选择
            productCarouselSection
            
            // 2. 新增订阅文案
            Text(viewModel.renewHintText)
                .font(.system(size: 12))
                .foregroundColor(bottomHintColor)
                .padding(.top, -4)
            
            // 3. 购买按钮
            bottomActionSection
            
            // 4. 法律条款 (紧贴安全区)
            footerSection
                .padding(.bottom, safeBottom > 0 ? 0 : 10)
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Layout

private extension SubscriptionView {
    var horizontalPadding: CGFloat { 18 }
    
    var isPadPaywallLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }
    
    var bottomSurfaceOverlap: CGFloat {
#if os(macOS)
        74
#else
        88
#endif
    }
    
    var headerContentTopPush: CGFloat {
#if os(macOS)
        54
#else
        68
#endif
    }
    
    var titleSubtitleSpacing: CGFloat { 8 }
    var titleBenefitsSpacing: CGFloat { 10 }
    
    
    
    var productCardWidth: CGFloat {
#if os(macOS)
        260
#else
        160
#endif
    }
    
    func heroHeight(proxy: GeometryProxy) -> CGFloat {
#if os(macOS)
        return 300
#else
        return proxy.size.height * 0.48
#endif
    }
    
    func topSafeTopInset(_ proxy: GeometryProxy) -> CGFloat {
#if os(macOS)
        return 18
#else
        return max(proxy.safeAreaInsets.top, 14)
#endif
    }
    
    func bottomSafeBottomInset(_ proxy: GeometryProxy) -> CGFloat {
#if os(macOS)
        return 16
#else
        return max(proxy.safeAreaInsets.bottom, 10)
#endif
    }
}

// MARK: - Background

private extension SubscriptionView {
    var pageBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: colorScheme == .dark ? "071018" : "F4F7FA"),
                Color(hex: colorScheme == .dark ? "0B1822" : "EDF2F6"),
                Color(hex: colorScheme == .dark ? "0C1620" : "E9EEF3")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func subscriptionHeroImageBackground(height: CGFloat) -> some View {
        ZStack {
            Image("SubscriptionHeroBackground")
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: heroImageTopOverlay, location: 0.0),
                    .init(color: heroImageTitleOverlay, location: 0.42),
                    .init(color: heroImageMidOverlay, location: 0.62),
                    .init(color: bottomSurfaceFill.opacity(colorScheme == .dark ? 0.92 : 0.78), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)

            if isHeroAnimationEnabled {
                FlowingParticleLayer(colorScheme: colorScheme)
                    .opacity(colorScheme == .dark ? 0.18 : 0.10)
                    .frame(height: height)
            }
        }
        .frame(height: height)
    }

    var heroImageTopOverlay: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.18)
    }

    var heroImageTitleOverlay: Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.42)
    }

    var heroImageMidOverlay: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.34)
    }

    func immersiveHeroBackground(height: CGFloat) -> some View {
        SubscriptionImmersiveHeroBackground(colorScheme: colorScheme)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
    
}

// MARK: - Top Bar

private extension SubscriptionView {
    
    var topBarForeground: Color {
        colorScheme == .dark ? .white : Color(hex: "0B2230")
    }
    
    var topBarBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.72)
    }
    
    var topBarStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }
}

// MARK: - Header

private extension SubscriptionView {
    var heroTitleColor: Color {
        colorScheme == .dark ? .white : Color(hex: "092432")
    }
    
    var heroSubtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.80) : Color(hex: "2F4F5F").opacity(0.86)
    }
    
    var heroBulletColor: Color {
        colorScheme == .dark ? Color(hex: "A7F3D0") : Color(hex: "0F766E")
    }
    
    var heroDetailForeground: Color {
        colorScheme == .dark ? .white : Color(hex: "0B2230")
    }
    
    var heroDetailBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.74)
    }
}

// MARK: - Bottom Area

private extension SubscriptionView {
    
    var bottomHintColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.60) : Color(hex: "5D727D")
    }
}

// MARK: - Product Carousel

private extension SubscriptionView {
    var productCarouselSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.subscriptionProducts) { product in
                    CompactSubscriptionProductCard(
                        product: product,
                        isSelected: viewModel.isSelected(product),
                        isRecommended: viewModel.isRecommended(product),
                        priceText: viewModel.productPriceText(product),
                        periodText: viewModel.productPeriodText(product),
                        pointGiftText: viewModel.productPointGiftText(product),
                        colorScheme: colorScheme
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.90)) {
                            viewModel.selectProduct(product)
                        }
                    }
                    .frame(width: productCardWidth)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
    }
}

private struct CompactSubscriptionProductCard: View {
    let product: BillingProduct
    let isSelected: Bool
    let isRecommended: Bool
    let priceText: String
    let periodText: String?
    let pointGiftText: String?
    let colorScheme: ColorScheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(product.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let periodText {
                    Text(periodText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(subtitleColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(priceText)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(titleColor)
                    
                    if let pointGiftText {
                        Text(pointGiftText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(giftColor)
                            .lineLimit(1)
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? selectedAccent : subtitleColor)
                    
                    Text(isSelected ? "已选择" : "选择")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? selectedAccent : subtitleColor)
                    
                    Spacer()
                    
                    if isRecommended {
                        Text("推荐")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(recommendedTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(recommendedBackground)
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardOverlay)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                colorScheme == .dark
                ? Color.white.opacity(0.055)
                : Color(hex: "F9FBFC").opacity(0.92)
            )
    }
    
    @ViewBuilder
    var cardOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(baseStroke, lineWidth: 1)
        
        if isSelected {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: "38BDF8"),
                            Color(hex: "34D399"),
                            Color(hex: "818CF8")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
    }
    
    var baseStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(hex: "C9D7E2").opacity(0.55)
    }
    
    var titleColor: Color {
        colorScheme == .dark ? .white : Color(hex: "10212E")
    }
    
    var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color(hex: "5B6B78")
    }
    
    var giftColor: Color {
        colorScheme == .dark ? Color(hex: "A7F3D0") : Color(hex: "0F766E")
    }
    
    var selectedAccent: Color {
        colorScheme == .dark ? Color(hex: "A7F3D0") : Color(hex: "0F766E")
    }
    
    var recommendedBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color(hex: "E8F7F3")
    }
    
    var recommendedTextColor: Color {
        colorScheme == .dark ? .white : Color(hex: "0F766E")
    }
}

private struct PadBenefitFeatureCard: View {
    let line: SubscriptionViewModel.SubscriptionBenefitLine
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 42, height: 42)
                
                Image(systemName: line.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let detail = line.detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }
    
    var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.78)
    }
    
    var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(hex: "C9D7E2").opacity(0.55)
    }
    
    var iconBackground: Color {
        line.highlighted
        ? Color(hex: "14B8A6").opacity(colorScheme == .dark ? 0.18 : 0.12)
        : Color(hex: "6366F1").opacity(colorScheme == .dark ? 0.18 : 0.11)
    }
    
    var iconColor: Color {
        line.highlighted ? Color(hex: "5EEAD4") : Color(hex: "8B5CF6")
    }
    
    var titleColor: Color {
        colorScheme == .dark ? .white : Color(hex: "10212E")
    }
    
    var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(hex: "5B6B78")
    }
}

private struct PadSubscriptionProductCard: View {
    let product: BillingProduct
    let isSelected: Bool
    let isRecommended: Bool
    let priceText: String
    let periodText: String?
    let pointGiftText: String?
    let colorScheme: ColorScheme
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(titleColor)
                            .lineLimit(2)
                        
                        if let periodText {
                            Text(periodText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(subtitleColor)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    if isRecommended {
                        Text("推荐")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: "8B5CF6")))
                    }
                }
                
                Text(priceText)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                
                if let pointGiftText {
                    Text(pointGiftText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(giftColor)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                HStack(spacing: 7) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Text(isSelected ? "已选择" : "选择")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(isSelected ? selectedAccent : subtitleColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardOverlay)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82))
    }
    
    @ViewBuilder
    var cardOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(baseStroke, lineWidth: 1)
        
        if isSelected {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "E879F9"), Color(hex: "8B5CF6"), Color(hex: "3B82F6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.4
                )
        }
    }
    
    var baseStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color(hex: "C9D7E2").opacity(0.70)
    }
    
    var titleColor: Color {
        colorScheme == .dark ? .white : Color(hex: "10212E")
    }
    
    var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color(hex: "5B6B78")
    }
    
    var giftColor: Color {
        colorScheme == .dark ? Color(hex: "A7F3D0") : Color(hex: "0F766E")
    }
    
    var selectedAccent: Color {
        colorScheme == .dark ? Color(hex: "C084FC") : Color(hex: "7C3AED")
    }
}

// MARK: - CTA + Footer

private extension SubscriptionView {
    var bottomActionSection: some View {
        VStack(spacing: 10) {
            if !viewModel.footerPriceText.isEmpty {
                Text(viewModel.footerPriceText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(bottomMetaColor)
            }
            
            Button {
                if viewModel.isAgreement {
                    Task {
                        await viewModel.continuePurchase()
                    }
                    return
                }
                showPaidServiceAgreement = true
            } label: {
                HStack(spacing: 8) {
                    if viewModel.purchasingProductCode != nil {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    
                    Text(viewModel.primaryButtonTitle)
                        .font(.system(size: 16, weight: .bold))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: buttonGradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canContinue)
            .opacity(viewModel.canContinue ? 1 : 0.6)
        }
    }
    
    var buttonGradientColors: [Color] {
        colorScheme == .dark
        ? [Color(hex: "0F766E"), Color(hex: "2563EB")]
        : [Color(hex: "0F766E"), Color(hex: "3B82F6")]
    }
    
    var bottomMetaColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(hex: "4D6673")
    }
    
    var footerSection: some View {
        AgreementRow(isAgreed: $viewModel.isAgreement, content:
                        "为保障您的合法权益，请同意[《Talkify 付费服务协议》（含自动续费条款）](dreamai://vip-protocol)", openURL: { url in
            if url.host() == "vip-protocol" {
                router.navigate(to: .openURL(AgreementURLs.paid))
            }
        })
        .frame(maxWidth: .infinity)
    }
    
    var footerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.60) : Color(hex: "6A7A86")
    }
    
    func footerLinkButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundColor(footerColor)
        }
        .buttonStyle(.plain)
    }
    
    var agreementTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color(hex: "6B7280")
    }

    var agreementLinkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color(hex: "374151")
    }
    
}

// MARK: - Floating Message

private extension SubscriptionView {
    @ViewBuilder
    func floatingMessageOverlay(bottomInset: CGFloat) -> some View {
        if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
            InlineFloatingMessageCard(
                title: "购买提示",
                message: errorMessage,
                tint: Color(hex: "D35454"),
                colorScheme: colorScheme
            )
            .padding(.horizontal, 16)
            .padding(.bottom, bottomInset + 48)
        } else if let feedbackMessage = viewModel.feedbackMessage {
            InlineFloatingMessageCard(
                title: "操作结果",
                message: feedbackMessage,
                tint: Color(hex: "2E9E5B"),
                colorScheme: colorScheme
            )
            .padding(.horizontal, 16)
            .padding(.bottom, bottomInset + 48)
        }
    }
}

private struct InlineFloatingMessageCard: View {
    let title: String
    let message: String
    let tint: Color
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(primaryText)
            
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(secondaryText)
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 16, x: 0, y: 8)
    }
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.white.opacity(0.92)
    }
    
    var primaryText: Color {
        colorScheme == .dark ? .white : Color(hex: "0A2230")
    }
    
    var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.75) : Color(hex: "536B77")
    }
}

// MARK: - Immersive Background

struct SubscriptionImmersiveHeroBackground: View {
    let colorScheme: ColorScheme
    
    // 使用 TimelineView 驱动，确保每一帧都在平滑流动
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // 1. 绘制背景底色
                let baseColor = colorScheme == .dark ? Color(hex: "020617") : Color(hex: "F3F7FA")
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(baseColor))
                
                // 2. 定义流体混合层
                // 使用 .screen 混合模式能让颜色交织时变亮，模拟 AI 能量感
                context.addFilter(.blur(radius: 60))
                
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // 绘制 4 个互相穿插的流体球
                drawBlob(context: context, size: size, color: Color(hex: "3B82F6"),
                         speed: 0.6, offsetRange: 120, time: time, seed: 1)
                drawBlob(context: context, size: size, color: Color(hex: "A855F7"),
                         speed: 0.4, offsetRange: 150, time: time, seed: 2)
                drawBlob(context: context, size: size, color: Color(hex: "10B981"),
                         speed: 0.5, offsetRange: 100, time: time, seed: 3)
                drawBlob(context: context, size: size, color: Color(hex: "6366F1"),
                         speed: 0.3, offsetRange: 180, time: time, seed: 4)
            }
        }
        .ignoresSafeArea()
        .overlay(
            // 顶层覆盖：消除边缘“灰尘”感，增加高级质感
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.3 : 0.5)
                .ignoresSafeArea()
        )
    }
    
    // 核心算法：利用三角函数控制球体的非线性流动
    private func drawBlob(context: GraphicsContext, size: CGSize, color: Color, speed: Double, offsetRange: CGFloat, time: Double, seed: Double) {
        var innerContext = context
        
        let xPos = size.width / 2 + cos(time * speed + seed) * offsetRange
        let yPos = size.height / 2 + sin(time * speed * 0.8 + seed * 1.5) * offsetRange
        
        let blobSize = size.width * 1.5 // 稍微加大，确保流动覆盖面
        let rect = CGRect(x: xPos - blobSize/2, y: yPos - blobSize/2, width: blobSize, height: blobSize)
        
        // --- 核心修复逻辑 ---
        if colorScheme == .dark {
            // 深色模式：使用滤色，让颜色交汇处发光
            innerContext.blendMode = .screen
            innerContext.opacity = 0.4
        } else {
            // 浅色模式：改用普通叠加或 normal，并适当提高透明度
            // 绝对不能用 .screen 或 .plusLighter，否则在白底上看不见
            innerContext.blendMode = .normal
            innerContext.opacity = 0.20 // 浅色模式透明度不宜过高，否则会显得脏
        }
        
        // 使用径向渐变，但要确保中心点颜色足够浓郁
        innerContext.fill(Circle().path(in: rect), with: .radialGradient(
            Gradient(colors: [color, color.opacity(0)]),
            center: CGPoint(x: rect.midX, y: rect.midY),
            startRadius: 0,
            endRadius: blobSize / 2
        ))
    }
}

private struct FlowingParticleLayer: View {
    let colorScheme: ColorScheme
    
    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                
                Canvas { ctx, size in
                    for index in 0..<28 {
                        let progress = CGFloat((time * 0.07) + Double(index) * 0.11)
                        let x = (progress.truncatingRemainder(dividingBy: 1.25)) * size.width
                        let y = (CGFloat((index * 37) % 100) / 100.0) * size.height
                        + sin(progress * 8) * 12
                        
                        let rect = CGRect(x: x, y: y, width: 3.5, height: 3.5)
                        ctx.fill(
                            Path(ellipseIn: rect),
                            with: .color(
                                colorScheme == .dark
                                ? .white.opacity(0.52)
                                : Color(hex: "2C6E7A").opacity(0.30)
                            )
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
private struct SubscriptionProductCard: View {
    let product: BillingProduct
    let isSelected: Bool
    let isRecommended: Bool
    let priceText: String
    let periodText: String?
    let pointGiftText: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        if let periodText {
                            Text(periodText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if isRecommended {
                        Text("推荐")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "FF8A00"))
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(priceText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let pointGiftText {
                        Text(pointGiftText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "6D28D9"))
                    }
                }
                
                Spacer(minLength: 0)
                
                HStack {
                    Text(isSelected ? "已选择" : "点击选择")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : Color.accentColor)
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .white : Color.accentColor)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(backgroundShape)
            .overlay(borderShape)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                isSelected
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [Color(hex: "1D4ED8"), Color(hex: "7C3AED")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                : AnyShapeStyle(Color.systemBackground)
            )
    }
    
    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                isSelected ? Color.clear : Color.black.opacity(0.06),
                lineWidth: 1
            )
    }
}



private struct SubscriptionPurchaseSuccessSheet: View {
    let state: SubscriptionViewModel.PurchaseSuccessState
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Color(hex: "FF8A00"))
            
            VStack(spacing: 8) {
                Text("订阅开通成功")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(state.productName)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                resultRow(title: "当前余额", value: "\(state.availablePoints.cleanDisplay) 点")
                resultRow(title: "订阅状态", value: state.subscriptionActive ? "已生效" : "未生效")
                
                if let currentSubscription = state.currentSubscription, !currentSubscription.isEmpty {
                    resultRow(title: "当前订阅", value: currentSubscription)
                }
            }
            
            Button(action: onClose) {
                Text("开始体验")
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

private extension SubscriptionView {
    var skeletonBaseFill: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.08)
        : Color.black.opacity(0.06)
    }
    
    var skeletonSecondaryFill: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.05)
        : Color.black.opacity(0.04)
    }
    func skeletonBlock(
        width: CGFloat? = nil,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(skeletonBaseFill)
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(skeletonSecondaryFill.opacity(0.35))
            }
    }
}
private extension SubscriptionView {
    func loadingContent(safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            loadingHeaderArea
                .padding(.bottom, 30)
            
            loadingBottomArea(safeBottom: safeBottom)
        }
        .skeletonShimmer(active: true)
    }
    
    var loadingHeaderArea: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                skeletonBlock(width: 170, height: 34, cornerRadius: 12)
                skeletonBlock(width: 210, height: 15, cornerRadius: 8)
            }
            
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(skeletonBaseFill)
                            .frame(width: 18, height: 18)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            skeletonBlock(
                                width: index.isMultiple(of: 2) ? 150 : 178,
                                height: 15,
                                cornerRadius: 8
                            )
                            
                            skeletonBlock(
                                width: index.isMultiple(of: 2) ? 110 : 132,
                                height: 11,
                                cornerRadius: 6
                            )
                        }
                        
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                
                Text("正在加载订阅方案…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(heroSubtitleColor)
            }
            .padding(.top, 4)
        }
    }
    
    func loadingBottomArea(safeBottom: CGFloat) -> some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(skeletonBaseFill)
                            .frame(width: productCardWidth, height: 126)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        colorScheme == .dark
                                        ? Color.white.opacity(0.06)
                                        : Color.black.opacity(0.04),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .padding(.bottom, 2)
            }
            
            skeletonBlock(width: 180, height: 12, cornerRadius: 6)
            
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(skeletonBaseFill)
                .frame(height: 52)
            
            HStack(spacing: 12) {
                skeletonBlock(width: 48, height: 12, cornerRadius: 6)
                Rectangle()
                    .fill(skeletonSecondaryFill)
                    .frame(width: 1, height: 12)
                skeletonBlock(width: 48, height: 12, cornerRadius: 6)
                Rectangle()
                    .fill(skeletonSecondaryFill)
                    .frame(width: 1, height: 12)
                skeletonBlock(width: 62, height: 12, cornerRadius: 6)
            }
            .padding(.bottom, safeBottom > 0 ? 0 : 10)
        }
        .padding(.horizontal, 18)
    }
}

private struct SkeletonShimmerModifier: ViewModifier {
    let isActive: Bool
    let speed: Double
    
    @State private var phase: CGFloat = -0.8
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { proxy in
                        let size = proxy.size
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color.white.opacity(0.0), location: 0.35),
                                .init(color: Color.white.opacity(0.38), location: 0.5),
                                .init(color: Color.white.opacity(0.0), location: 0.65),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: size.width * 0.55)
                        .rotationEffect(.degrees(18))
                        .offset(x: size.width * phase)
                        .blendMode(.plusLighter)
                        .mask {
                            content
                        }
                        .task {
                            guard phase == -0.8 else { return }
                            withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                                phase = 1.2
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

private extension View {
    func skeletonShimmer(active: Bool = true, speed: Double = 1.15) -> some View {
        modifier(SkeletonShimmerModifier(isActive: active, speed: speed))
    }
}

struct PaidServiceAgreementSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let content: String
    let onAgree: () -> Void
    let onCancel: () -> Void
    let openURL: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 18) {

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top)

            Text((try? AttributedString(markdown: content)) ?? AttributedString(content))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .foregroundColor(agreementTextColor)
                .tint(Color(hex: "22C55E"))
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme != nil {
                        openURL?(url)
                        return .handled
                    }
                    return .systemAction
                })

            VStack(spacing: 10) {
                Button(action: onAgree) {
                    Text("同意并购买")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "061108"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
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
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Capsule()
                                .fill(
                                    colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.black.opacity(0.05)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
    
    var agreementTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color(hex: "6B7280")
    }

    var agreementLinkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color(hex: "374151")
    }
}

struct AgreementRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isAgreed: Bool
    
    let content: String
    
    let openURL: ((URL) -> Void)?
    
    var body: some View {
        Toggle(isOn: $isAgreed) {
            Text((try? AttributedString(markdown: content)) ?? AttributedString(content))
                .font(.system(size: 13))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(agreementTextColor)
                .tint(agreementLinkColor) // 使用 App 的主题色高亮
        }
        .toggleStyle(CheckboxToggleStyle()) // 自定义的勾选框样式
        .padding(.horizontal)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme != nil {
                openURL?(url)
                return .handled
            }
            return .systemAction
        })
    }
    
    var agreementTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color(hex: "6B7280")
    }

    var agreementLinkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color(hex: "374151")
    }
}
    

struct CheckboxToggleStyle: ToggleStyle {
    
    @Environment(\.colorScheme) private var colorScheme
    
    
    func makeBody(configuration: Configuration) -> some View {
        Button {
            // 点击时切换勾选状态
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 3) {
                // 根据勾选状态展示不同的图标
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                    .font(.system(size: 13, weight: .semibold))
                    // 稍微加一点点击时的动画缩放，质感更好
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isOn)
                
                // 这里会接收外界传给 Toggle 的 Label 内容（即你的协议文本）
                configuration.label
            }
        }
        .buttonStyle(.plain) // 消除 Button 默认的置灰高亮和边距影响
    }
    
}
