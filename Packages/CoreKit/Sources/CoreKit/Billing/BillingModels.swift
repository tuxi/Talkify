import Foundation

public struct BillingBenefits: Codable, Sendable, Hashable {
    public let removeWatermark: Bool
    public let priorityQueue: Bool
    public let allow1080p: Bool
//    public let allowCustomAspectRatio: Bool
//    public let dailyFreeTaskLimit: Int
//    public let dailyDurationLimitSec: Int
    public let pointPackDiscountRate: Double

    enum CodingKeys: String, CodingKey {
        case removeWatermark = "remove_watermark"
        case priorityQueue = "priority_queue"
        case allow1080p = "allow_1080p"
//        case allowCustomAspectRatio = "allow_custom_aspect_ratio"
//        case dailyFreeTaskLimit = "daily_free_task_limit"
//        case dailyDurationLimitSec = "daily_duration_limit_sec"
        case pointPackDiscountRate = "point_pack_discount_rate"
    }

    public init(
        removeWatermark: Bool = false,
        priorityQueue: Bool = false,
        allow1080p: Bool = false,
        allowCustomAspectRatio: Bool = false,
        dailyFreeTaskLimit: Int = 0,
        dailyDurationLimitSec: Int = 0,
        pointPackDiscountRate: Double = 0
    ) {
        self.removeWatermark = removeWatermark
        self.priorityQueue = priorityQueue
        self.allow1080p = allow1080p
//        self.allowCustomAspectRatio = allowCustomAspectRatio
//        self.dailyFreeTaskLimit = dailyFreeTaskLimit
//        self.dailyDurationLimitSec = dailyDurationLimitSec
        self.pointPackDiscountRate = pointPackDiscountRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.removeWatermark = try container.decodeIfPresent(Bool.self, forKey: .removeWatermark) ?? false
        self.priorityQueue = try container.decodeIfPresent(Bool.self, forKey: .priorityQueue) ?? false
        self.allow1080p = try container.decodeIfPresent(Bool.self, forKey: .allow1080p) ?? false
//        self.allowCustomAspectRatio = try container.decodeIfPresent(Bool.self, forKey: .allowCustomAspectRatio) ?? false
//        self.dailyFreeTaskLimit = try container.decodeIfPresent(Int.self, forKey: .dailyFreeTaskLimit) ?? 0
//        self.dailyDurationLimitSec = try container.decodeIfPresent(Int.self, forKey: .dailyDurationLimitSec) ?? 0
        self.pointPackDiscountRate = try container.decodeIfPresent(Double.self, forKey: .pointPackDiscountRate) ?? 0
    }
}

public struct BillingProduct: Codable, Sendable, Identifiable {
    public let productCode: String
    public let displayName: String
    public let description: String?
    public let priceAmount: Int
    public let currency: String
    public let pointAmount: Int
    public let periodUnit: String?
    public let periodCount: Int?
    public let benefits: BillingBenefits?
    public let benefitItems: [BillingBenefitItem]?

    public var id: String { productCode }

    enum CodingKeys: String, CodingKey {
        case productCode = "product_code"
        case displayName = "display_name"
        case description
        case priceAmount = "price_amount"
        case currency
        case pointAmount = "point_amount"
        case periodUnit = "period_unit"
        case periodCount = "period_count"
        case benefits
        case benefitItems = "benefit_items"
    }

    public init(
        productCode: String,
        displayName: String,
        description: String?,
        priceAmount: Int,
        currency: String,
        pointAmount: Int,
        periodUnit: String?,
        periodCount: Int?,
        benefits: BillingBenefits?,
        benefitItems: [BillingBenefitItem]?
    ) {
        self.productCode = productCode
        self.displayName = displayName
        self.description = description
        self.priceAmount = priceAmount
        self.currency = currency
        self.pointAmount = pointAmount
        self.periodUnit = periodUnit
        self.periodCount = periodCount
        self.benefits = benefits
        self.benefitItems = benefitItems
    }
}

public struct BillingBenefitItem: Codable, Sendable, Identifiable, Hashable {
    public let code: String
    public let title: String
    public let description: String
    public let highlighted: Bool

    public var id: String { code }

    public init(
        code: String,
        title: String,
        description: String,
        highlighted: Bool
    ) {
        self.code = code
        self.title = title
        self.description = description
        self.highlighted = highlighted
    }
}

public struct BillingProductList: Codable, Sendable {
    public let subscriptionProducts: [BillingProduct]
    public let pointPackProducts: [BillingProduct]

    enum CodingKeys: String, CodingKey {
        case subscriptionProducts = "subscription_products"
        case pointPackProducts = "point_pack_products"
    }
}

public struct BillingWallet: Codable, Sendable {
    public let userID: Int
    public let availablePoints: Int
    public let frozenPoints: Int
    public let currentSubscription: String?
    public let subscriptionActive: Bool
    public let subscriptionExpiredAt: Int?
    public let currentPeriodUsed: Int
    public let pointDiscountRate: Double
    public let canUse1080p: Bool
    public let canRemoveWatermark: Bool
    public let canUsePriorityQueue: Bool
    public let canUseCustomAspectRatio: Bool
    public let dailyFreeRemain: Int
    public let dailyDurationRemainSec: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case availablePoints = "available_points"
        case frozenPoints = "frozen_points"
        case currentSubscription = "current_subscription"
        case subscriptionActive = "subscription_active"
        case subscriptionExpiredAt = "subscription_expired_at"
        case currentPeriodUsed = "current_period_used"
        case pointDiscountRate = "point_discount_rate"
        case canUse1080p = "can_use_1080p"
        case canRemoveWatermark = "can_remove_watermark"
        case canUsePriorityQueue = "can_use_priority_queue"
        case canUseCustomAspectRatio = "can_use_custom_aspect_ratio"
        case dailyFreeRemain = "daily_free_remain"
        case dailyDurationRemainSec = "daily_duration_remain_sec"
    }
}

public struct BillingEntitlements: Codable, Sendable {
    public let userID: Int
    public let subscriptionActive: Bool
    public let currentSubscription: String?
    public let subscriptionExpiredAt: Int?
    public let pointDiscountRate: Double
    public let canUse1080p: Bool
    public let canRemoveWatermark: Bool
    public let canUsePriorityQueue: Bool
    public let canUseCustomAspectRatio: Bool
    public let dailyFreeLimit: Int
    public let dailyFreeRemain: Int
    public let dailyDurationLimitSec: Int
    public let dailyDurationRemainSec: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case subscriptionActive = "subscription_active"
        case currentSubscription = "current_subscription"
        case subscriptionExpiredAt = "subscription_expired_at"
        case pointDiscountRate = "point_discount_rate"
        case canUse1080p = "can_use_1080p"
        case canRemoveWatermark = "can_remove_watermark"
        case canUsePriorityQueue = "can_use_priority_queue"
        case canUseCustomAspectRatio = "can_use_custom_aspect_ratio"
        case dailyFreeLimit = "daily_free_limit"
        case dailyFreeRemain = "daily_free_remain"
        case dailyDurationLimitSec = "daily_duration_limit_sec"
        case dailyDurationRemainSec = "daily_duration_remain_sec"
    }
}

public struct BillingQuoteRequest: Sendable {
    public let sceneType: String
    public let sceneKey: String
    public let durationSeconds: Int
    public let resolution: String
    public let shotCount: Int
    public let enhanceMode: String?
    public let model: String?
    public let mode: String?
    public let imageCount: Int

    public init(
        sceneType: String,
        sceneKey: String,
        durationSeconds: Int,
        resolution: String,
        shotCount: Int,
        enhanceMode: String? = nil,
        model: String? = nil,
        mode: String? = nil,
        imageCount: Int
    ) {
        self.sceneType = sceneType
        self.sceneKey = sceneKey
        self.durationSeconds = durationSeconds
        self.resolution = resolution
        self.shotCount = shotCount
        self.enhanceMode = enhanceMode
        self.model = model
        self.mode = mode
        self.imageCount = imageCount
    }
}

public struct BillingQuoteResponse: Codable, Sendable {
    public let estimatedPoints: Int
    public let pricingSnapshot: [String: JSONValue]?
    public let entitlementOK: Bool
    public let insufficientReason: String?

    enum CodingKeys: String, CodingKey {
        case estimatedPoints = "estimated_points"
        case pricingSnapshot = "pricing_snapshot"
        case entitlementOK = "entitlement_ok"
        case insufficientReason = "insufficient_reason"
    }
}

public struct BillingCTA: Codable, Sendable, Identifiable {
    public let action: String
    public let title: String
    public let productCode: String?
    public let emphasized: Bool

    public var id: String { "\(action)-\(productCode ?? "")-\(title)" }

    enum CodingKeys: String, CodingKey {
        case action
        case title
        case productCode = "product_code"
        case emphasized
    }
}

public struct BillingSubscriptionCenter: Codable, Sendable {
    public let userID: Int
    public let wallet: BillingWallet
    public let products: BillingProductList
    public let currentBenefitItems: [BillingBenefitItem]
    public let primaryCTA: BillingCTA?
    public let secondaryCTAs: [BillingCTA]
    public let supportRestorePurchase: Bool
    public let supportManageSubscription: Bool
    public let manageSubscriptionTarget: String?
    public let recommendedSubscriptionProductCode: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case wallet
        case products
        case currentBenefitItems = "current_benefit_items"
        case primaryCTA = "primary_cta"
        case secondaryCTAs = "secondary_ctas"
        case supportRestorePurchase = "support_restore_purchase"
        case supportManageSubscription = "support_manage_subscription"
        case manageSubscriptionTarget = "manage_subscription_target"
        case recommendedSubscriptionProductCode = "recommended_subscription_product_code"
    }
}

public struct BillingCheckInStatus: Codable, Sendable {
    public let userID: Int
    public let checkedInToday: Bool
    public let rewardPoints: Int
    public let availablePoints: Int
    public let checkInDate: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case checkedInToday = "checked_in_today"
        case rewardPoints = "reward_points"
        case availablePoints = "available_points"
        case checkInDate = "checkin_date"
    }
}

public struct BillingVerifyIOSOrderRequest: Sendable {
    public let productCode: String
    public let transactionID: String
    public let originalTransactionID: String?
    public let receiptData: String?
    public let purchaseToken: String?

    public init(
        productCode: String,
        transactionID: String,
        originalTransactionID: String? = nil,
        receiptData: String? = nil,
        purchaseToken: String? = nil
    ) {
        self.productCode = productCode
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.receiptData = receiptData
        self.purchaseToken = purchaseToken
    }
}

public struct BillingOrderResult: Codable, Sendable {
    public let orderNo: String
    public let productType: String
    public let subscriptionActive: Bool
    public let availablePoints: Int

    enum CodingKeys: String, CodingKey {
        case orderNo = "order_no"
        case productType = "product_type"
        case subscriptionActive = "subscription_active"
        case availablePoints = "available_points"
    }
}

public struct BillingPointLedger: Codable, Sendable, Identifiable {
    public let id: Int
    public let changeType: String
    public let direction: String
    public let points: Int
    public let bizType: String
    public let bizID: String
    public let remark: String?
    public let extra: [String: JSONValue]?
    public let displayTitle: String?
    public let displayDescription: String?
    public let displayCategory: String?
    public let displayPointsText: String?
    public let balanceAfter: Int
    public let frozenAfter: Int
    public let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case changeType = "change_type"
        case direction
        case points
        case bizType = "biz_type"
        case bizID = "biz_id"
        case remark
        case extra
        case displayTitle = "display_title"
        case displayDescription = "display_description"
        case displayCategory = "display_category"
        case displayPointsText = "display_points_text"
        case balanceAfter = "balance_after"
        case frozenAfter = "frozen_after"
        case createdAt = "created_at"
    }
}

public struct BillingPointLedgerList: Codable, Sendable {
    public let items: [BillingPointLedger]
    public let total: Int
    public let page: Int
    public let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case pageSize = "page_size"
    }
}
