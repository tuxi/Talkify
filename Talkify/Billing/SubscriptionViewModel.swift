//
//  SubscriptionViewModel.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/16.
//

import SwiftUI
import Combine
import CoreKit
import DesignKit
#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
final class SubscriptionViewModel: ObservableObject {
    struct PurchaseSuccessState: Identifiable {
        let id = UUID()
        let productCode: String
        let productName: String
        let availablePoints: Double
        let subscriptionActive: Bool
        let currentSubscription: String?
        let originalTransactionID: String?
    }

    struct SubscriptionBenefitLine: Identifiable, Hashable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String?
        let highlighted: Bool
    }

    @Published var isLoading = false
    @Published var isRestoring = false
    @Published var purchasingProductCode: String?
    @Published var errorMessage: String?
    @Published var feedbackMessage: String?
    @Published var purchaseSuccessState: PurchaseSuccessState?
    @Published var selectedProductCode: String?
    @Published var showPlanComparison = false
    @Published private(set) var publicPage: BillingPublicSubscriptionPage?
    @Published var isAgreement = false
    @Published var authManager: AuthManager
    
#if canImport(StoreKit)
    @Published private(set) var storeProducts: [String: Product] = [:]
#endif

    private let billingManager: BillingManager
    private let billingService: BillingService

#if canImport(StoreKit)
    private var transactionUpdatesTask: Task<Void, Never>?
    private var handledTransactionIDs = Set<UInt64>()
#endif

    init(billingManager: BillingManager, billingService: BillingService, authManager: AuthManager) {
        self.billingManager = billingManager
        self.billingService = billingService
        self.authManager = authManager
#if canImport(StoreKit)
        startTransactionUpdatesListener()
#endif
    }

    deinit {
#if canImport(StoreKit)
        transactionUpdatesTask?.cancel()
#endif
    }

    var subscriptionProducts: [BillingProduct] {
        availableSubscriptionProducts(from: publicPage?.products ?? [])
    }

    var selectedProduct: BillingProduct? {
        if let selectedProductCode,
           let product = subscriptionProducts.first(where: { $0.productCode == selectedProductCode }) {
            return product
        }
        return subscriptionProducts.first
    }

    var titleText: String {
        publicPage?.title ?? "Talkify Pro"
    }

    var subtitleText: String {
        publicPage?.subtitle ?? "解锁更完整的创意生成体验"
    }

    var renewHintText: String {
        publicPage?.renewHintText ?? "订阅后自动续费，您也可以随时取消"
    }

    var restoreButtonTitle: String {
        if isRestoring {
            return TalkifyLocalized.string("billing.restoring")
        }
        return /*publicPage?.restoreButtonTitle ?? */TalkifyLocalized.string("billing.restore_purchases")
    }

    var termsURLString: String {
        publicPage?.termsURL ?? AgreementURLs.terms.absoluteString
    }

    var privacyURLString: String {
        publicPage?.privacyURL ?? AgreementURLs.privacy.absoluteString
    }

    var primaryButtonTitle: String {
        guard let selectedProduct else { return TalkifyLocalized.string("common.action.continue") }
        if purchasingProductCode == selectedProduct.productCode {
            return TalkifyLocalized.string("common.loading")
        }
        return TalkifyLocalized.string("common.action.continue")
    }

    var footerPriceText: String {
        guard let selectedProduct else { return "" }
        let price = displayPrice(for: selectedProduct)
        if selectedProduct.pointAmount > 0 {
            return "\(price) · \(String(format: TalkifyLocalized.string("billing.point_gift_format"), String(selectedProduct.pointAmount)))"
        }
        return price
    }

    var canContinue: Bool {
        selectedProduct != nil && purchasingProductCode == nil
    }

    var comparisonRows: [PlanComparisonRow] {
        buildComparisonRows(products: subscriptionProducts)
    }

    var recommendedSubscriptionProductCode: String? {
        guard let recommended = publicPage?.recommendedSubscriptionProductCode,
              recommended != activeSubscriptionProductCode else {
            return subscriptionProducts.first?.productCode
        }
        return recommended
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let page = try await billingService.fetchPublicSubscriptionPage(platform: "ios")
            self.publicPage = page

            if selectedProductCode == nil {
                selectedProductCode = recommendedSubscriptionProductCode ?? subscriptionProducts.first?.productCode
            } else if selectedProduct == nil {
                selectedProductCode = recommendedSubscriptionProductCode ?? subscriptionProducts.first?.productCode
            }

            isLoading = false
            
            // 异步加载 StoreKit 商品，不阻塞首屏展示
            #if canImport(StoreKit)
            Task { [weak self] in
                guard let self else { return }
                await self.loadStoreProducts()
            }
            #endif

        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func selectProduct(_ product: BillingProduct) {
        selectedProductCode = product.productCode
    }

    func benefitLines(for product: BillingProduct?) -> [SubscriptionBenefitLine] {
        guard let product else { return [] }

        if let benefitItems = product.benefitItems, !benefitItems.isEmpty {
            return benefitItems.map {
                SubscriptionBenefitLine(
                    icon: iconForBenefitTitle($0.title),
                    title: $0.title,
                    detail: $0.description.isEmpty ? nil : $0.description,
                    highlighted: $0.highlighted
                )
            }
        }

        guard let benefits = product.benefits else {
            if product.pointAmount > 0 {
                return [
                    .init(
                        icon: "sparkles",
                        title: String(format: TalkifyLocalized.string("billing.point_gift_format"), String(product.pointAmount)),
                        detail: "购买后点数自动发放到钱包",
                        highlighted: true
                    )
                ]
            }
            return []
        }

        var lines: [SubscriptionBenefitLine] = []

        if benefits.allow1080p {
            lines.append(.init(
                icon: "video.badge.checkmark",
                title: "支持 1080p 输出",
                detail: nil,
                highlighted: true
            ))
        }

        if benefits.removeWatermark {
            lines.append(.init(
                icon: "drop",
                title: "支持去水印",
                detail: nil,
                highlighted: true
            ))
        }

        if benefits.priorityQueue {
            lines.append(.init(
                icon: "bolt.fill",
                title: "优先队列",
                detail: "高峰期更快开始生成",
                highlighted: true
            ))
        }

        if benefits.pointPackDiscountRate > 0, benefits.pointPackDiscountRate < 1 {
            lines.append(.init(
                icon: "tag.fill",
                title: "点数包折扣",
                detail: "折扣系数 \(benefits.pointPackDiscountRate.cleanDisplay)",
                highlighted: false
            ))
        }

        if product.pointAmount > 0 {
            lines.append(.init(
                icon: "sparkles",
                title: String(format: TalkifyLocalized.string("billing.point_gift_format"), String(product.pointAmount)),
                detail: "开通后自动发放",
                highlighted: true
            ))
        }

        return lines
    }

    func productPriceText(_ product: BillingProduct) -> String {
        displayPrice(for: product)
    }

    func productPeriodText(_ product: BillingProduct) -> String? {
        guard let periodUnit = product.periodUnit,
              let periodCount = product.periodCount else { return nil }
        return String(format: TalkifyLocalized.string("billing.period_format"), "\(periodCount)\(localizedPeriodUnit(periodUnit))")
    }

    func productPointGiftText(_ product: BillingProduct) -> String? {
        guard product.pointAmount > 0 else { return nil }
        return String(format: TalkifyLocalized.string("billing.point_gift_format"), String(product.pointAmount))
    }

    func isSelected(_ product: BillingProduct) -> Bool {
        selectedProduct?.productCode == product.productCode
    }

    func isRecommended(_ product: BillingProduct) -> Bool {
        recommendedSubscriptionProductCode == product.productCode
    }

    func continuePurchase() async {
        guard let selectedProduct else { return }
#if canImport(StoreKit)
        await purchase(product: selectedProduct)
#endif
    }

    func restorePurchase() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
#if canImport(StoreKit)
            try await AppStore.sync()
#endif
            await billingManager.refreshAllIfNeeded(maxAge: 0)
            feedbackMessage = TalkifyLocalized.string("billing.restore_complete")
            ToastContext.shared.show(TalkifyLocalized.string("billing.restore_complete"), style: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

#if canImport(StoreKit)
    func purchase(product: BillingProduct) async {
        guard let storeProduct = storeProducts[product.productCode] else {
            errorMessage = "未能获取 App Store 商品信息，请稍后重试。"
            return
        }

        purchasingProductCode = product.productCode
        errorMessage = nil
        feedbackMessage = nil
        defer { purchasingProductCode = nil }

        do {
            let purchaseStartedAt = Date()
            let purchaseResult = try await storeProduct.purchase()
            switch purchaseResult {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    let verifyResult = try await verifyTransaction(transaction, productCode: product.productCode)
                    handledTransactionIDs.insert(transaction.id)
                    await transaction.finish()

                    guard transaction.purchaseDate >= purchaseStartedAt.addingTimeInterval(-2) else {
                        feedbackMessage = "订阅状态已同步。"
                        return
                    }

                    purchaseSuccessState = PurchaseSuccessState(
                        productCode: product.productCode,
                        productName: product.displayName,
                        availablePoints: verifyResult.availableTalkifyPoints
                            ?? Double(verifyResult.availablePoints) / 20_000,
                        subscriptionActive: verifyResult.subscriptionActive,
                        currentSubscription: billingManager.wallet?.currentSubscription,
                        originalTransactionID: String(transaction.originalID)
                    )
                    ToastContext.shared.show("购买成功", style: .success)

                case .unverified(_, let error):
                    errorMessage = "App Store 交易校验失败：\(error.localizedDescription)"
                }

            case .pending:
                feedbackMessage = "购买请求已提交，正在等待 App Store 完成确认。"
            case .userCancelled:
                feedbackMessage = "已取消购买。"
            @unknown default:
                errorMessage = "出现未知的购买结果，请稍后查看钱包状态。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadStoreProducts() async {
        let productIDs = Array(Set(subscriptionProducts.map(\.productCode)))
        guard !productIDs.isEmpty else {
            storeProducts = [:]
            return
        }

        do {
            let appStoreProducts = try await Product.products(for: productIDs)
            storeProducts = Dictionary(uniqueKeysWithValues: appStoreProducts.map { ($0.id, $0) })
        } catch {
            if errorMessage == nil {
                errorMessage = "App Store 商品加载失败：\(error.localizedDescription)"
            }
        }
    }

    private func verifyTransaction(
        _ transaction: StoreKit.Transaction,
        productCode: String
    ) async throws -> BillingOrderResult {
        let result = try await billingService.verifyIOSOrder(
            BillingVerifyIOSOrderRequest(
                productCode: productCode,
                transactionID: String(transaction.id),
                originalTransactionID: String(transaction.originalID),
                receiptData: "",
                purchaseToken: ""
            )
        )

        await billingManager.refreshAllIfNeeded(maxAge: 0)
        return result
    }

    private func startTransactionUpdatesListener() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }

                switch result {
                case .verified(let transaction):
                    await self.handleTransactionUpdate(transaction)
                case .unverified(_, let error):
                    await MainActor.run {
                        if self.errorMessage == nil {
                            self.errorMessage = "App Store 交易校验失败：\(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func handleTransactionUpdate(_ transaction: StoreKit.Transaction) async {
        guard authManager.isLoggedIn else { return }
        guard !handledTransactionIDs.contains(transaction.id) else { return }

        do {
            _ = try await verifyTransaction(transaction, productCode: transaction.productID)
            handledTransactionIDs.insert(transaction.id)
            await transaction.finish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
#endif

    private func localizedPeriodUnit(_ rawValue: String) -> String {
        switch rawValue {
        case "month": return TalkifyLocalized.string("billing.period.month")
        case "year": return TalkifyLocalized.string("billing.period.year")
        case "week": return TalkifyLocalized.string("billing.period.week")
        case "day": return TalkifyLocalized.string("billing.period.day")
        default: return rawValue
        }
    }

    private var activeSubscriptionProductCode: String? {
        if let wallet = billingManager.wallet,
           wallet.subscriptionActive,
           let currentSubscription = wallet.currentSubscription,
           !currentSubscription.isEmpty {
            return currentSubscription
        }

        if let entitlements = billingManager.entitlements,
           entitlements.subscriptionActive,
           let currentSubscription = entitlements.currentSubscription,
           !currentSubscription.isEmpty {
            return currentSubscription
        }

        return nil
    }

    private func availableSubscriptionProducts(from products: [BillingProduct]) -> [BillingProduct] {
        activeSubscriptionProductCode == nil ? products : []
    }

    private func displayPrice(for product: BillingProduct) -> String {
#if canImport(StoreKit)
        if let storeProduct = storeProducts[product.productCode] {
            return storeProduct.displayPrice
        }
#endif
		return CurrencyFormatter.currencyString(fromMinorUnits: product.priceAmount, currencyCode: product.currency)
    }

    private func iconForBenefitTitle(_ title: String) -> String {
        if title.contains("1080") { return "video.badge.checkmark" }
        if title.contains("去水印") { return "drop" }
        if title.contains("优先") { return "bolt.fill" }
        if title.contains("比例") { return "rectangle.compress.vertical" }
        if title.contains("点") { return "sparkles" }
        if title.contains("次数") { return "calendar" }
        return "checkmark.circle.fill"
    }

    private func buildComparisonRows(products: [BillingProduct]) -> [PlanComparisonRow] {
        let features = collectFeatureKeys(from: products)
        return features.map { feature in
            PlanComparisonRow(
                featureTitle: feature.title,
                featureKey: feature.key,
                values: products.map { product in
                    comparisonValue(for: feature.key, product: product)
                }
            )
        }
    }

    private func collectFeatureKeys(from products: [BillingProduct]) -> [(key: String, title: String)] {
        var keys: [(String, String)] = [
            ("points", TalkifyLocalized.string("billing.point_gift_format")),
            ("1080p", "1080p 输出"),
            ("watermark", "去水印"),
            ("priority", "优先队列"),
//            ("aspect_ratio", "自定义比例"),
//            ("daily_tasks", "每日免费次数"),
//            ("daily_duration", "每日生成时长")
        ]

        let customTitles = products
            .flatMap { $0.benefitItems ?? [] }
            .map { ($0.title, $0.title) }

        for item in customTitles where !keys.contains(where: { $0.0 == item.0 }) {
            keys.append(item)
        }
        return keys
    }

    private func comparisonValue(for key: String, product: BillingProduct) -> String {
        if key == "points" {
            return product.pointAmount > 0 ? String(format: TalkifyLocalized.string("billing.point_gift_format"), String(product.pointAmount)) : "—"
        }

        if let benefitItems = product.benefitItems,
           let matched = benefitItems.first(where: { $0.title == key }) {
            return matched.description.isEmpty ? "支持" : matched.description
        }

        guard let benefits = product.benefits else { return "—" }

        switch key {
        case "1080p":
            return benefits.allow1080p ? "支持" : "—"
        case "watermark":
            return benefits.removeWatermark ? "支持" : "—"
        case "priority":
            return benefits.priorityQueue ? "支持" : "—"
//        case "aspect_ratio":
//            return benefits.allowCustomAspectRatio ? "支持" : "—"
//        case "daily_tasks":
//            return benefits.dailyFreeTaskLimit > 0 ? "\(benefits.dailyFreeTaskLimit)" : "—"
//        case "daily_duration":
//            return benefits.dailyDurationLimitSec > 0 ? "\(benefits.dailyDurationLimitSec) 秒" : "—"
        default:
            return "—"
        }
    }
}

struct PlanComparisonRow: Identifiable, Hashable {
    let id = UUID()
    let featureTitle: String
    let featureKey: String
    let values: [String]
}
