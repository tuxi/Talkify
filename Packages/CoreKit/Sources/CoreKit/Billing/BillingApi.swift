import Foundation

public enum BillingApi: ApiEndpoint {
    case subscriptionCenter(platform: String?)
    case publicSubscriptionPage(platform: String?)
    case products(platform: String?)
    case wallet
    case entitlements
    case checkInStatus
    case checkIn
    case quote(BillingQuoteRequest)
    case verifyIOSOrder(BillingVerifyIOSOrderRequest)
    case restoreIOSOrder(originalTransactionID: String)
    case pointLedgers(page: Int, pageSize: Int, changeType: String?)
    

    public var path: String {
        switch self {
        case .subscriptionCenter:
            return "billing/subscription-center"
        case .products:
            return "billing/products"
        case .wallet:
            return "billing/wallet"
        case .entitlements:
            return "billing/entitlements"
        case .checkInStatus:
            return "billing/check-in/status"
        case .checkIn:
            return "billing/check-in"
        case .quote:
            return "billing/quote"
        case .verifyIOSOrder:
            return "billing/orders/verify-ios"
        case .restoreIOSOrder:
            return "billing/orders/restore-ios"
        case .pointLedgers:
            return "billing/point-ledgers"
        case .publicSubscriptionPage:
            return "public/billing/subscription-page"
        }
    }

    public var method: HTTPMethod {
        switch self {
        case .subscriptionCenter,
                .products,
                .wallet,
                .entitlements,
                .checkInStatus,
                .pointLedgers,
                .publicSubscriptionPage:
            return .get
        case .checkIn,
                .quote,
                .verifyIOSOrder,
                .restoreIOSOrder:
            return .post
        }
    }

    public var parameters: [String: Sendable] {
        switch self {
        case .subscriptionCenter(let platform):
            if let platform, !platform.isEmpty {
                return ["platform": platform]
            }
            return [:]
        case .publicSubscriptionPage(let platform):
            if let platform, !platform.isEmpty {
                return ["platform": platform]
            }
            return [:]
        case .products(let platform):
            if let platform, !platform.isEmpty {
                return ["platform": platform]
            }
            return [:]
        case .wallet, .entitlements, .checkInStatus, .checkIn:
            return [:]
        case .quote(let request):
            var parameters: [String: Sendable] = [
                "scene_type": request.sceneType,
                "scene_key": request.sceneKey,
                "duration_seconds": request.durationSeconds,
                "resolution": request.resolution,
                "shot_count": request.shotCount,
                "image_count": request.imageCount,
            ]
            if let enhanceMode = request.enhanceMode, !enhanceMode.isEmpty {
                parameters["enhance_mode"] = enhanceMode
            }
            if let model = request.model, !model.isEmpty {
                parameters["model"] = model
            }
            return parameters
        case .verifyIOSOrder(let request):
            var parameters: [String: Sendable] = [
                "product_code": request.productCode,
                "transaction_id": request.transactionID
            ]
            if let originalTransactionID = request.originalTransactionID, !originalTransactionID.isEmpty {
                parameters["original_transaction_id"] = originalTransactionID
            }
            if let receiptData = request.receiptData {
                parameters["receipt_data"] = receiptData
            }
            if let purchaseToken = request.purchaseToken {
                parameters["purchase_token"] = purchaseToken
            }
            return parameters
        case .restoreIOSOrder(let originalTransactionID):
            return [
                "original_transaction_id": originalTransactionID
            ]
        case .pointLedgers(let page, let pageSize, let changeType):
            var parameters: [String: Sendable] = [
                "page": page,
                "page_size": pageSize
            ]
            if let changeType, !changeType.isEmpty {
                parameters["change_type"] = changeType
            }
            return parameters
        }
    }

    public var encoding: ApiParameterEncoding {
        switch self {
        case .subscriptionCenter, .products, .wallet, .entitlements, .checkInStatus, .pointLedgers, .publicSubscriptionPage:
            return .url
        case .checkIn, .quote, .verifyIOSOrder, .restoreIOSOrder:
            return .json
        }
    }
}
