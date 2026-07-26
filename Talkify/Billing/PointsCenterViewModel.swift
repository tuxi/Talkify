//
//  PointsCenterViewModel.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/17.
//

import SwiftUI
import CoreKit
import DesignKit
#if canImport(StoreKit)
import StoreKit
#endif
import Combine

@MainActor
final class PointsCenterViewModel: ObservableObject {
    struct PurchaseSuccessState: Identifiable {
        let id = UUID()
        let productCode: String
        let productName: String
        let availablePoints: Int
        let subscriptionActive: Bool
        let currentSubscription: String?
        let originalTransactionID: String?
    }

    @Published var isLoading = false
    @Published var isRestoring = false
    @Published var isCheckingIn = false
    @Published var purchasingProductCode: String?
    @Published var errorMessage: String?
    @Published var feedbackMessage: String?
    @Published var purchaseSuccessState: PurchaseSuccessState?
    @Published var restoreErrorMessage: String?
    @Published var originalTransactionID = ""

#if canImport(StoreKit)
    @Published private(set) var storeProducts: [String: Product] = [:]
#endif

    let billingManager: BillingManager
    let billingService: BillingService
    private var lastFailedProductCode: String?
#if canImport(StoreKit)
    private var transactionUpdatesTask: Task<Void, Never>?
    private var handledTransactionIDs = Set<UInt64>()
#endif
    
    @Published var selectedPointPackProductCode: String?
    
    @Published var isAgreement = false
    
    var selectedPointPackProduct: BillingProduct? {
        if let selectedPointPackProductCode,
           let matched = pointPackProducts.first(where: { $0.productCode == selectedPointPackProductCode }) {
            return matched
        }
        return pointPackProducts.first
    }

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

    var wallet: BillingWallet? { billingManager.wallet }
    var entitlements: BillingEntitlements? { billingManager.entitlements }
    var products: BillingProductList? { billingManager.products }
    var subscriptionCenter: BillingSubscriptionCenter? { billingManager.subscriptionCenter }
    var checkInStatus: BillingCheckInStatus? { billingManager.checkInStatus }

    var pointPackProducts: [BillingProduct] {
        subscriptionCenter?.products.pointPackProducts ?? products?.pointPackProducts ?? []
    }

    var currentSubscriptionText: String {
        guard let currentSubscription = wallet?.currentSubscription else {
            return wallet?.subscriptionActive == true ? "订阅已开通" : "未开通订阅"
        }
        
        guard let subscriptionProducts = self.billingManager.products?.subscriptionProducts else {
            return currentSubscription
        }
        let index = subscriptionProducts.firstIndex {
            $0.productCode == currentSubscription
        }
        if let index {
            return subscriptionProducts[index].displayName
        }
        return currentSubscription.isEmpty ? "未开通" : currentSubscription
    }

    var availablePointsText: String {
        "\(wallet?.availablePoints ?? 0)"
    }

    var checkInRewardText: String {
        "\(checkInStatus?.rewardPoints ?? 0)"
    }

    var checkInButtonTitle: String {
        if isCheckingIn {
            return "签到中..."
        }
        return hasCheckedInToday ? "今日已签到" : "立即签到"
    }

    var checkInCardTitle: String {
        hasCheckedInToday ? "今日点数已领取" : "每日签到奖励"
    }

    var checkInCardSubtitle: String {
        if hasCheckedInToday, let checkInStatus {
            return "已在 \(checkInStatus.checkInDate) 完成签到，点数已到账钱包"
        }
        return "今天签到可领取 \(checkInRewardText) 点，到账后可直接用于视频生成"
    }

    var checkInDateText: String {
        checkInStatus?.checkInDate ?? "—"
    }

    var hasCheckedInToday: Bool {
        checkInStatus?.checkedInToday == true
    }

    var checkInAvailablePointsText: String {
        "\(checkInStatus?.availablePoints ?? wallet?.availablePoints ?? 0)"
    }
    
    var restoreButtonTitle: String {
        isRestoring ? "恢复中..." : "恢复购买"
    }

    var frozenPointsText: String {
        "\(wallet?.frozenPoints ?? 0)"
    }

    var pointDiscountText: String {
        (wallet?.pointDiscountRate ?? 1).cleanDisplay
    }

    var canRestore: Bool {
        !isRestoring
    }

    var hasPurchasableProducts: Bool {
        !pointPackProducts.isEmpty
    }

    var failedPurchaseProduct: BillingProduct? {
        guard let lastFailedProductCode else { return nil }
        return pointPackProducts.first(where: { $0.productCode == lastFailedProductCode })
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let centerTask: Void = billingManager.refreshSubscriptionCenterIfNeeded(maxAge: 0)
        async let entitlementsTask: Void = billingManager.refreshEntitlementsIfNeeded(maxAge: 0)
//        async let checkInTask: Void = billingManager.refreshCheckInStatusIfNeeded(maxAge: 0)
        _ = await (centerTask, entitlementsTask)
        errorMessage = billingManager.lastErrorMessage

#if canImport(StoreKit)
        await loadStoreProducts()
#endif
        if selectedPointPackProductCode == nil {
            selectedPointPackProductCode = pointPackProducts.first?.productCode
        }
    }

    func performCheckIn() async {
        guard !hasCheckedInToday else {
            feedbackMessage = "今天已经签到过了"
            return
        }
        guard !isCheckingIn else { return }

        isCheckingIn = true
        errorMessage = nil
        feedbackMessage = nil
        defer { isCheckingIn = false }

        do {
            let result = try await billingManager.performCheckIn()
            NotificationCenter.default.post(name: .billingPointLedgerDidChange, object: nil)
            feedbackMessage = "签到成功，已到账 \(result.rewardPoints) 点"
            ToastContext.shared.show("签到成功 +\(result.rewardPoints) 点", style: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func selectPointPack(_ product: BillingProduct) {
        selectedPointPackProductCode = product.productCode
    }

    func sanitizeOriginalTransactionID() {
        let trimmed = originalTransactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != originalTransactionID {
            originalTransactionID = trimmed
        }
    }
    
    var primaryPurchaseButtonTitle: String {
        guard let product = selectedPointPackProduct else { return "立即购买" }
        if isPurchasing(product) {
            return "购买中..."
        }
        return "立即购买 \(productPriceText(product))"
    }
    
    func purchaseSelectedPointPack() async {
        guard let product = selectedPointPackProduct else { return }
    #if canImport(StoreKit)
        await purchase(product: product)
    #endif
    }

    func productPriceText(_ product: BillingProduct) -> String {
#if canImport(StoreKit)
        if let storeProduct = storeProducts[product.productCode] {
            return storeProduct.displayPrice
        }
#endif
		return CurrencyFormatter.currencyString(fromMinorUnits: product.priceAmount, currencyCode: product.currency)
    }

    func productTitle(_ product: BillingProduct) -> String {
        product.displayName
    }

    func productSubtitle(_ product: BillingProduct) -> String {
        let price = productPriceText(product)
        return "\(price) · \(product.pointAmount) 点"
    }

    func productBadgeText(_ product: BillingProduct) -> String? {
        if let discount = product.benefits?.pointPackDiscountRate,
           discount != 1 {
            return "折扣 \(discount.cleanDisplay)x"
        }
        return product.pointAmount >= 1000 ? "热门" : nil
    }

    func benefitLines(for product: BillingProduct) -> [String] {
        if let benefitItems = product.benefitItems, !benefitItems.isEmpty {
            return benefitItems.map {
                $0.description.isEmpty ? $0.title : "\($0.title) · \($0.description)"
            }
        }

        var lines: [String] = []
        lines.append("购买后点数直接发放到钱包")
        lines.append("可用于视频生成、加速和高级能力")
        if let discount = product.benefits?.pointPackDiscountRate {
            lines.append("点数包折扣系数 \(discount.cleanDisplay)")
        }
        return lines
    }

    func isPurchasing(_ product: BillingProduct) -> Bool {
        purchasingProductCode == product.productCode
    }

    func purchaseButtonTitle(for product: BillingProduct) -> String {
        isPurchasing(product) ? "购买中..." : "购买"
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

    func restorePurchase() async {
        isRestoring = true
        restoreErrorMessage = nil
        feedbackMessage = nil
        defer { isRestoring = false }

        do {
#if canImport(StoreKit)
            try await AppStore.sync()
#endif
            let trimmed = originalTransactionID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = try? await billingService.restoreIOSOrder(originalTransactionID: trimmed)
            }
            await billingManager.refreshAllIfNeeded(maxAge: 0)
            feedbackMessage = "恢复购买已完成"
            ToastContext.shared.show("恢复购买已完成", style: .success)
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
    }

#if canImport(StoreKit)
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
            let purchaseResult = try await storeProduct.purchase()
            switch purchaseResult {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    let verifyResult = try await verifyTransaction(transaction, productCode: product.productCode)
                    handledTransactionIDs.insert(transaction.id)
                    await transaction.finish()

                    originalTransactionID = String(transaction.originalID)
                    feedbackMessage = "购买成功，点数已发放到钱包。"
                    purchaseSuccessState = PurchaseSuccessState(
                        productCode: product.productCode,
                        productName: product.displayName,
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
        let productIDs = Array(Set(pointPackProducts.map(\.productCode)))
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
            let verifyResult = try await verifyTransaction(transaction, productCode: transaction.productID)
            handledTransactionIDs.insert(transaction.id)
            try await transaction.finish()
            originalTransactionID = String(transaction.originalID)
            feedbackMessage = "购买已完成，点数已自动同步到钱包。"
            purchaseSuccessState = PurchaseSuccessState(
                productCode: transaction.productID,
                productName: pointPackProducts.first(where: { $0.productCode == transaction.productID })?.displayName ?? transaction.productID,
                availablePoints: verifyResult.availablePoints,
                subscriptionActive: verifyResult.subscriptionActive,
                currentSubscription: billingManager.wallet?.currentSubscription,
                originalTransactionID: String(transaction.originalID)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
#endif
}
