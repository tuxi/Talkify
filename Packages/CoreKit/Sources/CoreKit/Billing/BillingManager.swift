import Foundation
import Observation

@Observable
@MainActor
public final class BillingManager {
    public private(set) var subscriptionCenter: BillingSubscriptionCenter?
    public private(set) var wallet: BillingWallet?
    public private(set) var entitlements: BillingEntitlements?
    public private(set) var products: BillingProductList?
    public private(set) var checkInStatus: BillingCheckInStatus?
    public private(set) var isRefreshing = false
    public var lastErrorMessage: String?

    private let service: BillingService
    private var lastWalletUpdatedAt: Date?
    private var lastProductsUpdatedAt: Date?
    private var lastEntitlementsUpdatedAt: Date?
    private var lastCheckInUpdatedAt: Date?

    public init(service: BillingService) {
        self.service = service
    }

    public func refreshAllIfNeeded(maxAge: TimeInterval = 300) async {
        async let walletTask: Void = refreshWalletIfNeeded(maxAge: maxAge)
        async let entitlementsTask: Void = refreshEntitlementsIfNeeded(maxAge: maxAge)
        async let productsTask: Void = refreshProductsIfNeeded(maxAge: maxAge)
        async let subscriptionCenterTask: Void = refreshSubscriptionCenterIfNeeded(maxAge: maxAge)
//        async let checkInTask: Void = refreshCheckInStatusIfNeeded(maxAge: maxAge)
        _ = await (walletTask, entitlementsTask, productsTask, subscriptionCenterTask)
    }

    public func refreshSubscriptionCenterIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastWalletUpdatedAt, Date().timeIntervalSince(lastWalletUpdatedAt) < maxAge, subscriptionCenter != nil {
            return
        }
        _ = try? await fetchSubscriptionCenter()
    }

    @discardableResult
    public func fetchSubscriptionCenter(platform: String? = "ios") async throws -> BillingSubscriptionCenter {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let subscriptionCenter = try await service.fetchSubscriptionCenter(platform: platform)
            self.subscriptionCenter = subscriptionCenter
            self.wallet = subscriptionCenter.wallet
            self.products = subscriptionCenter.products
            self.lastWalletUpdatedAt = Date()
            self.lastProductsUpdatedAt = Date()
            self.lastErrorMessage = nil
            return subscriptionCenter
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func refreshWalletIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastWalletUpdatedAt, Date().timeIntervalSince(lastWalletUpdatedAt) < maxAge, wallet != nil {
            return
        }
        _ = try? await fetchWallet()
    }

    public func refreshEntitlementsIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastEntitlementsUpdatedAt, Date().timeIntervalSince(lastEntitlementsUpdatedAt) < maxAge, entitlements != nil {
            return
        }
        _ = try? await fetchEntitlements()
    }

    public func refreshProductsIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastProductsUpdatedAt, Date().timeIntervalSince(lastProductsUpdatedAt) < maxAge, products != nil {
            return
        }
        _ = try? await fetchProducts()
    }

    public func refreshCheckInStatusIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastCheckInUpdatedAt, Date().timeIntervalSince(lastCheckInUpdatedAt) < maxAge, checkInStatus != nil {
            return
        }
        _ = try? await fetchCheckInStatus()
    }

    @discardableResult
    public func fetchWallet() async throws -> BillingWallet {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let wallet = try await service.fetchWallet()
            self.wallet = wallet
            self.lastWalletUpdatedAt = Date()
            self.lastErrorMessage = nil
            return wallet
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func fetchEntitlements() async throws -> BillingEntitlements {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let entitlements = try await service.fetchEntitlements()
            self.entitlements = entitlements
            self.lastEntitlementsUpdatedAt = Date()
            self.lastErrorMessage = nil
            return entitlements
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func fetchProducts(platform: String? = "ios") async throws -> BillingProductList {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let products = try await service.fetchProducts(platform: platform)
            self.products = products
            self.lastProductsUpdatedAt = Date()
            self.lastErrorMessage = nil
            return products
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func fetchCheckInStatus() async throws -> BillingCheckInStatus {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let status = try await service.fetchCheckInStatus()
            self.checkInStatus = status
            self.lastCheckInUpdatedAt = Date()
            self.lastErrorMessage = nil
            return status
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func performCheckIn() async throws -> BillingCheckInStatus {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let status = try await service.performCheckIn()
            self.checkInStatus = status
            self.lastCheckInUpdatedAt = Date()
            self.lastErrorMessage = nil
            _ = try? await fetchSubscriptionCenter()
            return status
        } catch {
            self.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func clear() {
        subscriptionCenter = nil
        wallet = nil
        entitlements = nil
        products = nil
        checkInStatus = nil
        lastErrorMessage = nil
        lastWalletUpdatedAt = nil
        lastProductsUpdatedAt = nil
        lastEntitlementsUpdatedAt = nil
        lastCheckInUpdatedAt = nil
        isRefreshing = false
    }
}
