//
//  SubscriptionCenterViewModel.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/17.
//

import SwiftUI
import Combine
import CoreKit
import DesignKit
#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
final class SubscriptionCenterViewModel: ObservableObject {

    struct PurchaseSuccessState: Identifiable {
        let id = UUID()
        let productCode: String
        let productName: String
        let productType: String
        let availablePoints: Int
        let subscriptionActive: Bool
        let currentSubscription: String?
        let originalTransactionID: String?
    }

    struct SubscriptionBenefitLine: Identifiable, Equatable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String?
    }

    struct SubscriptionManagementItem: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
        let value: String?
    }

    struct PaymentRecordItem: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
        let amountText: String
        let statusText: String
    }

    @Published var originalTransactionID = ""
    @Published var isLoading = false
    @Published var isRestoring = false
    @Published var purchasingProductCode: String?
    @Published var errorMessage: String?
    @Published var feedbackMessage: String?
    @Published var purchaseSuccessState: PurchaseSuccessState?
    @Published var restoreErrorMessage: String?
    @Published var selectedSubscriptionProductCode: String?
    @Published var showManagementSheet = false

#if canImport(StoreKit)
    @Published private(set) var storeProducts: [String: Product] = [:]
#endif

    private let billingManager: BillingManager
    private let billingService: BillingService
    private var lastFailedProductCode: String?

#if canImport(StoreKit)
    private var transactionUpdatesTask: Task<Void, Never>?
    private var handledTransactionIDs = Set<UInt64>()
#endif

    init(billingManager: BillingManager, billingService: BillingService) {
        self.billingManager = billingManager
        self.billingService = billingService
#if canImport(StoreKit)
        startTransactionUpdatesListener()
#endif
    }

    deinit {
#if canImport(StoreKit)
        transactionUpdatesTask?.cancel()
#endif
    }

    // MARK: - Source Data

    var wallet: BillingWallet? { billingManager.wallet }
    var entitlements: BillingEntitlements? { billingManager.entitlements }
    var products: BillingProductList? { billingManager.products }
    var subscriptionCenter: BillingSubscriptionCenter? { billingManager.subscriptionCenter }

    var rawSubscriptionProducts: [BillingProduct] {
        subscriptionCenter?.products.subscriptionProducts ?? products?.subscriptionProducts ?? []
    }

    var subscriptionProducts: [BillingProduct] {
        availableSubscriptionProducts(
            from: rawSubscriptionProducts
        )
    }

    var pointPackProducts: [BillingProduct] {
        subscriptionCenter?.products.pointPackProducts ?? products?.pointPackProducts ?? []
    }

    var currentBenefitItems: [BillingBenefitItem] {
        subscriptionCenter?.currentBenefitItems ?? []
    }

    var primaryCTA: BillingCTA? {
        subscriptionCenter?.primaryCTA
    }

    var secondaryCTAs: [BillingCTA] {
        subscriptionCenter?.secondaryCTAs ?? []
    }

    var recommendedSubscriptionProductCode: String? {
        guard let recommended = subscriptionCenter?.recommendedSubscriptionProductCode,
              recommended != activeSubscriptionProductCode else {
            return subscriptionProducts.first?.productCode
        }
        return recommended
    }

    // MARK: - UI State

    var canRestore: Bool {
        !isRestoring
    }

    var isPurchasing: Bool {
        purchasingProductCode != nil
    }

    var failedPurchaseProduct: BillingProduct? {
        guard let lastFailedProductCode else { return nil }
        return (subscriptionProducts + pointPackProducts).first(where: { $0.productCode == lastFailedProductCode })
    }

    var hasActiveSubscription: Bool {
        wallet?.subscriptionActive == true || entitlements?.subscriptionActive == true
    }

    var selectedSubscriptionProduct: BillingProduct? {
        if let selectedSubscriptionProductCode,
            let matched = subscriptionProducts.first(where: { $0.productCode == selectedSubscriptionProductCode }) {
            return matched
        }
        if let activeSubscriptionProductCode,
           let matched = rawSubscriptionProducts.first(where: { $0.productCode == activeSubscriptionProductCode }) {
            return matched
        }
        return subscriptionProducts.first
    }

    var canPurchaseSelectedSubscription: Bool {
        guard !hasActiveSubscription else { return false }
#if canImport(StoreKit)
        guard let selectedSubscriptionProduct else { return false }
        return storeProducts[selectedSubscriptionProduct.productCode] != nil && !isPurchasing
#else
        return selectedSubscriptionProduct != nil && !isPurchasing
#endif
    }
    
    var currentSubscriptionName: String {
        guard let currentSubscription = wallet?.currentSubscription else { return "未开通订阅" }
        
        guard let subscriptionProducts = self.billingManager.products?.subscriptionProducts else {
            return currentSubscription
        }
        let index = subscriptionProducts.firstIndex {
            $0.productCode == currentSubscription
        }
        if let index {
            return subscriptionProducts[index].displayName
        }
        return currentSubscription
    }
    
    var currentPointsText: String {
        "\(wallet?.availablePoints ?? 0)"
    }

    var currentStatusBadgeText: String {
        hasActiveSubscription ? "已开通" : "未开通"
    }

    var heroTitle: String {
        hasActiveSubscription ? "你的 Talkify Pro 正在生效" : "开通 Talkify Pro"
    }

    var heroSubtitle: String {
        if hasActiveSubscription {
            if let expiry = expiryText() {
                return "\(currentSubscriptionName) · 到期 \(expiry)"
            }
            return currentSubscriptionName
        }

        if let product = selectedSubscriptionProduct {
            return "选择 \(product.displayName)，获得更高的 Agent 周额度和订阅周期额度"
        }

        return "获得更高的 Agent 周额度和订阅周期额度"
    }

    var heroPrimaryButtonTitle: String {
        if hasActiveSubscription {
            return "管理订阅"
        }

        if let selectedSubscriptionProduct {
            return "立即开通 \(selectedSubscriptionProduct.displayName)"
        }
        return "立即开通"
    }

    var heroSecondaryButtonTitle: String {
        hasActiveSubscription ? "查看当前权益" : "查看方案权益"
    }

    var purchasingTitle: String {
        guard let purchasingProductCode,
              let product = (subscriptionProducts + pointPackProducts).first(where: { $0.productCode == purchasingProductCode }) else {
            return "正在处理购买"
        }
        return product.periodUnit == nil ? "正在购买点数包" : "正在开通订阅"
    }

    var purchasingMessage: String {
        "已拉起 App Store 购买流程，完成支付后会立即调用服务端验单并刷新钱包与权益。"
    }

    // MARK: - Management Sheet

    var managementSummaryItems: [SubscriptionManagementItem] {
        [
            SubscriptionManagementItem(
                title: "当前套餐",
                subtitle: "当前正在生效的订阅方案",
                value: currentSubscriptionName
            ),
            SubscriptionManagementItem(
                title: "订阅状态",
                subtitle: "当前会员开通状态",
                value: hasActiveSubscription ? "已开通" : "未开通"
            ),
            SubscriptionManagementItem(
                title: "到期时间",
                subtitle: "当前订阅预计到期时间",
                value: expiryText() ?? "--"
            ),
            SubscriptionManagementItem(
                title: "可用点数",
                subtitle: "当前账户可直接使用的点数",
                value: currentPointsText
            )
        ]
    }

    var paymentRecords: [PaymentRecordItem] {
        if let wallet, wallet.subscriptionActive {
            return [
                PaymentRecordItem(
                    title: currentSubscriptionName,
                    subtitle: expiryText().map { "最近一次同步 · 到期 \($0)" } ?? "最近一次同步记录",
                    amountText: "--",
                    statusText: "已同步"
                )
            ]
        }
        return []
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        _ = try? await billingManager.fetchSubscriptionCenter()
        await billingManager.refreshEntitlementsIfNeeded(maxAge: 0)
        errorMessage = billingManager.lastErrorMessage

        if selectedSubscriptionProductCode == nil {
            selectedSubscriptionProductCode =
                recommendedSubscriptionProductCode
                ?? subscriptionProducts.first?.productCode
        } else if selectedSubscriptionProduct == nil {
            selectedSubscriptionProductCode =
                recommendedSubscriptionProductCode
                ?? subscriptionProducts.first?.productCode
        }

#if canImport(StoreKit)
        await loadStoreProducts()
#endif
    }

    func sanitizeOriginalTransactionID() {
        let trimmed = originalTransactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != originalTransactionID {
            originalTransactionID = trimmed
        }
    }

    // MARK: - Selection

    func selectSubscriptionProduct(_ product: BillingProduct) {
        selectedSubscriptionProductCode = product.productCode
    }

    func isSelectedSubscription(_ product: BillingProduct) -> Bool {
        selectedSubscriptionProduct?.productCode == product.productCode
    }

    func isRecommendedSubscription(_ product: BillingProduct) -> Bool {
        product.productCode == recommendedSubscriptionProductCode
    }

    // MARK: - Derived Display

    func productSubtitle(_ product: BillingProduct) -> String {
        let price = displayPrice(for: product)
        let points = "\(product.pointAmount) 点"

        if let periodUnit = product.periodUnit, let periodCount = product.periodCount {
            return "\(price) · \(points) · 每\(periodCount)\(localizedPeriodUnit(periodUnit))"
        }

        return "\(price) · \(points)"
    }

    func benefitLines(for product: BillingProduct) -> [String] {
        if let benefitItems = product.benefitItems, !benefitItems.isEmpty {
            return benefitItems.map { item in
                item.description.isEmpty ? item.title : "\(item.title) · \(item.description)"
            }
        }

        guard let benefits = product.benefits else {
            return product.pointAmount > 0
                ? ["购买后点数直接发放到钱包，可用于生成和加速。"]
                : ["权益信息以服务端返回为准。"]
        }

        var lines: [String] = []
        if benefits.removeWatermark == true { lines.append("支持去水印") }
        if benefits.priorityQueue == true { lines.append("支持优先队列") }
        if benefits.allow1080p == true { lines.append("支持 1080p 输出") }
//        if benefits.allowCustomAspectRatio == true { lines.append("支持自定义比例") }
//        let dailyFreeTaskLimit = benefits.dailyFreeTaskLimit
//        if dailyFreeTaskLimit > 0 {
//            lines.append("每日免费次数 \(dailyFreeTaskLimit)")
//        }
//        let dailyDurationLimitSec = benefits.dailyDurationLimitSec
//        if dailyDurationLimitSec > 0 {
//            lines.append("每日可生成时长 \(dailyDurationLimitSec) 秒")
//        }
        let discount = benefits.pointPackDiscountRate
        if discount > 0 {
            lines.append("点数包折扣系数 \(discount.cleanDisplay)")
        }
        return lines
    }

    func selectedBenefitLines() -> [SubscriptionBenefitLine] {
        guard let product = selectedSubscriptionProduct else { return [] }

        if let benefitItems = product.benefitItems, !benefitItems.isEmpty {
            return benefitItems.map {
                SubscriptionBenefitLine(
                    icon: iconForBenefitTitle($0.title),
                    title: $0.title,
                    detail: $0.description.isEmpty ? nil : $0.description
                )
            }
        }

        return benefitLines(for: product).map {
            SubscriptionBenefitLine(
                icon: iconForBenefitText($0),
                title: $0,
                detail: nil
            )
        }
    }

    fileprivate func entitlementRows() -> [SubscriptionEntitlementRow] {
        if !currentBenefitItems.isEmpty {
            return currentBenefitItems.map {
                SubscriptionEntitlementRow(title: $0.title, value: $0.description)
            }
        }

        guard let entitlements else { return [] }

        return [
            SubscriptionEntitlementRow(title: "1080p 输出", value: entitlements.canUse1080p ? "已开启" : "不可用"),
            SubscriptionEntitlementRow(title: "去水印", value: entitlements.canRemoveWatermark ? "已开启" : "不可用"),
            SubscriptionEntitlementRow(title: "优先队列", value: entitlements.canUsePriorityQueue ? "已开启" : "不可用"),
//            SubscriptionEntitlementRow(title: "自定义比例", value: entitlements.canUseCustomAspectRatio ? "已开启" : "不可用"),
//            SubscriptionEntitlementRow(title: "每日免费次数", value: "\(entitlements.dailyFreeRemain) / \(entitlements.dailyFreeLimit)"),
//            SubscriptionEntitlementRow(title: "每日时长", value: "\(entitlements.dailyDurationRemainSec)s / \(entitlements.dailyDurationLimitSec)s")
        ]
    }

    func currentEntitlementSummary() -> [SubscriptionEntitlementRow] {
        if !currentBenefitItems.isEmpty {
            return currentBenefitItems.map {
                SubscriptionEntitlementRow(title: $0.title, value: $0.description)
            }
        }
        return entitlementRows()
    }

    func expiryText() -> String? {
        guard let timestamp = wallet?.subscriptionExpiredAt ?? entitlements?.subscriptionExpiredAt else {
            return nil
        }
        return DateFormatter.subscriptionDate.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    func purchaseButtonTitle(for product: BillingProduct) -> String {
        if purchasingProductCode == product.productCode {
            return product.periodUnit == nil ? "购买中..." : "订阅中..."
        }
        return product.periodUnit == nil ? "购买" : "订阅"
    }

    func isPurchasing(_ product: BillingProduct) -> Bool {
        purchasingProductCode == product.productCode
    }

    func dismissPurchaseSuccess() {
        purchaseSuccessState = nil
    }

    func retryLastFailedPurchase() async {
        guard let product = failedPurchaseProduct else { return }
#if canImport(StoreKit)
        await purchase(product: product)
#endif
    }

    // MARK: - Restore

    func restorePurchase() async {
        isRestoring = true
        restoreErrorMessage = nil
        feedbackMessage = nil
        defer { isRestoring = false }

        do {
#if canImport(StoreKit)
            try await AppStore.sync()
            if let transaction = await latestVerifiedSubscriptionTransaction() {
                let result = try await verifyTransaction(transaction, productCode: transaction.productID)
                await transaction.finish()
                originalTransactionID = String(transaction.originalID)
                feedbackMessage = result.subscriptionActive
                    ? "已通过 App Store 同步并完成服务端验单，当前订阅已恢复。"
                    : "恢复流程已完成，但当前没有有效订阅。"
                ToastContext.shared.show("恢复购买已完成", style: .success)
                return
            }
#endif

            let trimmedOriginalTransactionID = originalTransactionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOriginalTransactionID.isEmpty else {
                restoreErrorMessage = "未从 App Store 找到可恢复交易，请输入 original_transaction_id 后重试。"
                return
            }

            let result = try await billingService.restoreIOSOrder(originalTransactionID: trimmedOriginalTransactionID)
            await billingManager.refreshAllIfNeeded(maxAge: 0)
            feedbackMessage = result.subscriptionActive
                ? "已按原始订阅交易号恢复当前订阅摘要。"
                : "恢复请求已完成，但当前没有可用订阅状态。"
            ToastContext.shared.show("恢复购买已完成", style: .success)
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
    }

#if canImport(StoreKit)
    // MARK: - Purchase

    func purchase(product: BillingProduct) async {
        guard let storeProduct = storeProducts[product.productCode] else {
            errorMessage = "未能获取 App Store 商品信息，请稍后重试。"
            lastFailedProductCode = product.productCode
            return
        }

        purchasingProductCode = product.productCode
        errorMessage = nil
        feedbackMessage = nil
        lastFailedProductCode = nil
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
                    try await transaction.finish()
                    originalTransactionID = String(transaction.originalID)
                    guard transaction.purchaseDate >= purchaseStartedAt.addingTimeInterval(-2) else {
                        feedbackMessage = verifyResult.productType == "subscription"
                            ? "订阅状态已同步。"
                            : "点数状态已同步。"
                        return
                    }

                    feedbackMessage = verifyResult.productType == "subscription"
                        ? "购买成功，订阅与钱包状态已同步。"
                        : "购买成功，点数已发放到钱包。"
                    purchaseSuccessState = PurchaseSuccessState(
                        productCode: product.productCode,
                        productName: product.displayName,
                        productType: verifyResult.productType,
                        availablePoints: verifyResult.availablePoints,
                        subscriptionActive: verifyResult.subscriptionActive,
                        currentSubscription: billingManager.wallet?.currentSubscription,
                        originalTransactionID: String(transaction.originalID)
                    )
                    ToastContext.shared.show("购买成功", style: .success)

                case .unverified(_, let error):
                    errorMessage = "App Store 交易校验失败：\(error.localizedDescription)"
                    lastFailedProductCode = product.productCode
                }

            case .pending:
                feedbackMessage = "购买请求已提交，正在等待 App Store 完成确认。"
            case .userCancelled:
                feedbackMessage = "已取消购买。"
            @unknown default:
                errorMessage = "出现未知的购买结果，请稍后查看钱包状态。"
                lastFailedProductCode = product.productCode
            }
        } catch {
            errorMessage = error.localizedDescription
            lastFailedProductCode = product.productCode
        }
    }

    private func loadStoreProducts() async {
        let productIDs = Array(Set((subscriptionProducts + pointPackProducts).map(\.productCode)))
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

    private func latestVerifiedSubscriptionTransaction() async -> StoreKit.Transaction? {
        var latestTransaction: StoreKit.Transaction?

        for productCode in rawSubscriptionProducts.map(\.productCode) {
            guard let result = await StoreKit.Transaction.latest(for: productCode) else { continue }

            switch result {
            case .verified(let transaction):
                if let currentLatest = latestTransaction {
                    if transaction.purchaseDate > currentLatest.purchaseDate {
                        latestTransaction = transaction
                    }
                } else {
                    latestTransaction = transaction
                }
            case .unverified:
                continue
            }
        }

        return latestTransaction
    }

    private func verifyTransaction(_ transaction: StoreKit.Transaction, productCode: String) async throws -> BillingOrderResult {
        let result = try await billingService.verifyIOSOrder(
            BillingVerifyIOSOrderRequest(
                productCode: productCode,
                transactionID: String(transaction.id),
                originalTransactionID: String(transaction.originalID),
                receiptData: "",
                purchaseToken: ""
            )
        )
        _ = try? await billingManager.fetchSubscriptionCenter()
        await billingManager.refreshEntitlementsIfNeeded(maxAge: 0)
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
        guard !handledTransactionIDs.contains(transaction.id) else { return }

        do {
            _ = try await verifyTransaction(transaction, productCode: transaction.productID)
            handledTransactionIDs.insert(transaction.id)
            try await transaction.finish()
            originalTransactionID = String(transaction.originalID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
#endif

    // MARK: - Helpers

    private func localizedPeriodUnit(_ rawValue: String) -> String {
        switch rawValue {
        case "month":
            return "月"
        case "year":
            return "年"
        case "week":
            return "周"
        case "day":
            return "天"
        default:
            return rawValue
        }
    }

    private var activeSubscriptionProductCode: String? {
        if let wallet,
           wallet.subscriptionActive,
           let currentSubscription = wallet.currentSubscription,
           !currentSubscription.isEmpty {
            return currentSubscription
        }

        if let entitlements,
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
        if title.contains("去水印") { return "drop.triangle" }
        if title.contains("优先") { return "bolt.fill" }
        if title.contains("比例") { return "rectangle.expand.vertical" }
        if title.contains("点数") { return "sparkles" }
        return "checkmark.circle.fill"
    }

    private func iconForBenefitText(_ text: String) -> String {
        if text.contains("1080") { return "video.badge.checkmark" }
        if text.contains("去水印") { return "drop.triangle" }
        if text.contains("优先") { return "bolt.fill" }
        if text.contains("比例") { return "rectangle.expand.vertical" }
        if text.contains("点数") { return "sparkles" }
        if text.contains("免费") { return "gift.fill" }
        return "checkmark.circle.fill"
    }
}

struct SubscriptionEntitlementRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}
