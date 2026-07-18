import Foundation

public final class BillingService: @unchecked Sendable {
    private let apiProvider: ApiProvider

    public init(apiProvider: ApiProvider) {
        self.apiProvider = apiProvider
    }

    public func fetchSubscriptionCenter(platform: String? = "ios") async throws -> BillingSubscriptionCenter {
        try await apiProvider.request(endpoint: BillingApi.subscriptionCenter(platform: platform))
    }

    public func fetchPublicSubscriptionPage(platform: String?) async throws -> BillingPublicSubscriptionPage {
        try await apiProvider.request(endpoint: BillingApi.publicSubscriptionPage(platform: platform))
    }
    
    public func fetchProducts(platform: String? = "ios") async throws -> BillingProductList {
        try await apiProvider.request(endpoint: BillingApi.products(platform: platform))
    }

    public func fetchWallet() async throws -> BillingWallet {
        try await apiProvider.request(endpoint: BillingApi.wallet)
    }

    public func fetchEntitlements() async throws -> BillingEntitlements {
        try await apiProvider.request(endpoint: BillingApi.entitlements)
    }

    public func fetchCheckInStatus() async throws -> BillingCheckInStatus {
        try await apiProvider.request(endpoint: BillingApi.checkInStatus)
    }

    public func performCheckIn() async throws -> BillingCheckInStatus {
        try await apiProvider.request(endpoint: BillingApi.checkIn)
    }

    public func quote(_ request: BillingQuoteRequest) async throws -> BillingQuoteResponse {
        try await apiProvider.request(endpoint: BillingApi.quote(request))
    }

    public func verifyIOSOrder(_ request: BillingVerifyIOSOrderRequest) async throws -> BillingOrderResult {
        try await apiProvider.request(endpoint: BillingApi.verifyIOSOrder(request))
    }

    public func restoreIOSOrder(originalTransactionID: String) async throws -> BillingOrderResult {
        try await apiProvider.request(endpoint: BillingApi.restoreIOSOrder(originalTransactionID: originalTransactionID))
    }

    public func fetchPointLedgers(
        page: Int = 1,
        pageSize: Int = 20,
        changeType: String? = nil
    ) async throws -> BillingPointLedgerList {
        try await apiProvider.request(
            endpoint: BillingApi.pointLedgers(page: page, pageSize: pageSize, changeType: changeType)
        )
    }
}
