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
        let availablePoints: Double
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
            return wallet?.subscriptionActive == true ? TalkifyLocalized.string("billing.subscription_active_status") : TalkifyLocalized.string("billing.no_subscription")
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
        return currentSubscription.isEmpty ? TalkifyLocalized.string("billing.not_activated") : currentSubscription
    }

    var availablePointsText: String {
        (wallet?.availableTalkifyPoints ?? 0).cleanDisplay
    }

    var checkInRewardText: String {
        "\(checkInStatus?.rewardPoints ?? 0)"
    }

    var checkInButtonTitle: String {
        if isCheckingIn {
            return TalkifyLocalized.string("billing.checking_in")
        }
        return hasCheckedInToday ? TalkifyLocalized.string("billing.checked_in_today") : TalkifyLocalized.string("billing.check_in_now")
    }

    var checkInCardTitle: String {
        hasCheckedInToday ? TalkifyLocalized.string("billing.points_claimed_today") : TalkifyLocalized.string("billing.daily_checkin_reward")
    }

    var checkInCardSubtitle: String {
        if hasCheckedInToday, let checkInStatus {
            return "已在 \(checkInStatus.checkInDate) 完成签到，点数已到账钱包"
        }
        return "今天签到可领取 \(checkInRewardText) 点，到账后可用于 Talkify AI 能力"
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
        isRestoring ? TalkifyLocalized.string("billing.syncing") : TalkifyLocalized.string("billing.sync_purchases")
    }

    var frozenPointsText: String {
        (wallet?.frozenTalkifyPoints ?? 0).cleanDisplay
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

    var validityText: String {
        String(format: TalkifyLocalized.string("billing.validity_months_format"), String(pointPackProducts.first?.validityMonths ?? 12))
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
            feedbackMessage = TalkifyLocalized.string("billing.already_checked_in")
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
            feedbackMessage = String(format: TalkifyLocalized.string("billing.checkin_success"), String(result.rewardPoints))
            ToastContext.shared.show(String(format: TalkifyLocalized.string("billing.checkin_success_toast"), String(result.rewardPoints)), style: .success)
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
        guard let product = selectedPointPackProduct else { return TalkifyLocalized.string("billing.buy_now") }
        if isPurchasing(product) {
            return TalkifyLocalized.string("billing.purchasing")
        }
        return String(format: TalkifyLocalized.string("billing.buy_for_price"), productPriceText(product))
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
            return String(format: TalkifyLocalized.string("billing.discount_x"), discount.cleanDisplay)
        }
        return product.pointAmount >= 1000 ? TalkifyLocalized.string("billing.popular") : nil
    }

    func benefitLines(for product: BillingProduct) -> [String] {
        if let benefitItems = product.benefitItems, !benefitItems.isEmpty {
            return benefitItems.map {
                $0.description.isEmpty ? $0.title : "\($0.title) · \($0.description)"
            }
        }

        var lines: [String] = []
        lines.append(TalkifyLocalized.string("billing.points_after_purchase"))
        lines.append(TalkifyLocalized.string("billing.points_usage_desc"))
        lines.append("每笔购买独立有效 \(product.validityMonths ?? 12) 个月，优先使用最早到期点数")
        if let discount = product.benefits?.pointPackDiscountRate {
            lines.append("点数包折扣系数 \(discount.cleanDisplay)")
        }
        return lines
    }

    func isPurchasing(_ product: BillingProduct) -> Bool {
        purchasingProductCode == product.productCode
    }

    func purchaseButtonTitle(for product: BillingProduct) -> String {
        isPurchasing(product) ? TalkifyLocalized.string("billing.purchasing") : "购买"
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
            feedbackMessage = TalkifyLocalized.string("billing.purchase_sync_complete")
            ToastContext.shared.show(TalkifyLocalized.string("billing.purchase_sync_complete"), style: .success)
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
    }

#if canImport(StoreKit)
    func purchase(product: BillingProduct) async {
        guard let storeProduct = storeProducts[product.productCode] else {
            errorMessage = TalkifyLocalized.string("billing.product_info_failed")
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
                    feedbackMessage = TalkifyLocalized.string("billing.purchase_success_details")
                    purchaseSuccessState = PurchaseSuccessState(
                        productCode: product.productCode,
                        productName: product.displayName,
                        availablePoints: verifyResult.availableTalkifyPoints
                            ?? Double(verifyResult.availablePoints) / 20_000,
                        subscriptionActive: verifyResult.subscriptionActive,
                        currentSubscription: billingManager.wallet?.currentSubscription,
                        originalTransactionID: String(transaction.originalID)
                    )
                    ToastContext.shared.show(TalkifyLocalized.string("billing.purchase_success_toast"), style: .success)

                case .unverified(_, let error):
                    errorMessage = "App Store 交易校验失败：\(error.localizedDescription)"
                    lastFailedProductCode = product.productCode
                }

            case .pending:
                feedbackMessage = TalkifyLocalized.string("billing.purchase_submitted")
            case .userCancelled:
                feedbackMessage = TalkifyLocalized.string("billing.purchase_cancelled")
            @unknown default:
                errorMessage = TalkifyLocalized.string("billing.purchase_unknown_result")
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
            await transaction.finish()
            originalTransactionID = String(transaction.originalID)
            feedbackMessage = TalkifyLocalized.string("billing.purchase_auto_synced")
            purchaseSuccessState = PurchaseSuccessState(
                productCode: transaction.productID,
                productName: pointPackProducts.first(where: { $0.productCode == transaction.productID })?.displayName ?? transaction.productID,
                availablePoints: verifyResult.availableTalkifyPoints
                    ?? Double(verifyResult.availablePoints) / 20_000,
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
