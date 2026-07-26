import Foundation

public struct BillingBenefits: Codable, Sendable, Hashable {
    public let removeWatermark: Bool
    public let priorityQueue: Bool
    public let allow1080p: Bool
//    public let allowCustomAspectRatio: Bool
//    public let dailyFreeTaskLimit: Int
//    public let dailyDurationLimitSec: Int
    public let pointPackDiscountRate: Double
    public let agentPlanCode: String?
    public let agentPlanVersion: Int?
    public let agentWeeklyUnits: Int
    public let agentSubscriptionCycleUnits: Int

    enum CodingKeys: String, CodingKey {
        case removeWatermark = "remove_watermark"
        case priorityQueue = "priority_queue"
        case allow1080p = "allow_1080p"
//        case allowCustomAspectRatio = "allow_custom_aspect_ratio"
//        case dailyFreeTaskLimit = "daily_free_task_limit"
//        case dailyDurationLimitSec = "daily_duration_limit_sec"
        case pointPackDiscountRate = "point_pack_discount_rate"
        case agentPlanCode = "agent_plan_code"
        case agentPlanVersion = "agent_plan_version"
        case agentWeeklyUnits = "agent_weekly_units"
        case agentSubscriptionCycleUnits = "agent_subscription_cycle_units"
    }

    public init(
        removeWatermark: Bool = false,
        priorityQueue: Bool = false,
        allow1080p: Bool = false,
        allowCustomAspectRatio: Bool = false,
        dailyFreeTaskLimit: Int = 0,
        dailyDurationLimitSec: Int = 0,
        pointPackDiscountRate: Double = 0,
        agentPlanCode: String? = nil,
        agentPlanVersion: Int? = nil,
        agentWeeklyUnits: Int = 0,
        agentSubscriptionCycleUnits: Int = 0
    ) {
        self.removeWatermark = removeWatermark
        self.priorityQueue = priorityQueue
        self.allow1080p = allow1080p
//        self.allowCustomAspectRatio = allowCustomAspectRatio
//        self.dailyFreeTaskLimit = dailyFreeTaskLimit
//        self.dailyDurationLimitSec = dailyDurationLimitSec
        self.pointPackDiscountRate = pointPackDiscountRate
        self.agentPlanCode = agentPlanCode
        self.agentPlanVersion = agentPlanVersion
        self.agentWeeklyUnits = agentWeeklyUnits
        self.agentSubscriptionCycleUnits = agentSubscriptionCycleUnits
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
        self.agentPlanCode = try container.decodeIfPresent(String.self, forKey: .agentPlanCode)
        self.agentPlanVersion = try container.decodeIfPresent(Int.self, forKey: .agentPlanVersion)
        self.agentWeeklyUnits = try container.decodeIfPresent(Int.self, forKey: .agentWeeklyUnits) ?? 0
        self.agentSubscriptionCycleUnits = try container.decodeIfPresent(Int.self, forKey: .agentSubscriptionCycleUnits) ?? 0
    }
}

public struct BillingProduct: Codable, Sendable, Identifiable {
    public let productCode: String
    public let displayName: String
    public let description: String?
    public let priceAmount: Int
    public let currency: String
    public let pointAmount: Int
    public let usageUnitAmount: Int?
    public let validityMonths: Int?
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
        case usageUnitAmount = "usage_unit_amount"
        case validityMonths = "validity_months"
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
        usageUnitAmount: Int? = nil,
        validityMonths: Int? = nil,
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
        self.usageUnitAmount = usageUnitAmount
        self.validityMonths = validityMonths
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

public struct BillingQuotaPeriod: Codable, Sendable {
    public let unitsUsed: Int
    public let unitsLimit: Int
    public let unitsRemaining: Int
    public let tokensUsed: Int
    public let utilizationPercent: Double
    public let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case unitsUsed = "units_used"
        case unitsLimit = "units_limit"
        case unitsRemaining = "units_remaining"
        case tokensUsed = "tokens_used"
        case utilizationPercent = "utilization_pct"
        case resetsAt = "resets_at"
    }
}

public struct BillingWallet: Codable, Sendable {
    public let userID: Int
    public let availablePoints: Int
    public let frozenPoints: Int
    public let paidUsageUnits: Int
    public let frozenUsageUnits: Int
    public let availableTalkifyPoints: Double
    public let frozenTalkifyPoints: Double
    public let currentSubscription: String?
    public let subscriptionActive: Bool
    public let subscriptionExpiredAt: Int?
    public let planCode: String
    public let planVersion: Int
    public let quotaPolicy: String
    public let weekly: BillingQuotaPeriod?
    public let subscriptionCycle: BillingQuotaPeriod?
    public let currentFundingSource: String?
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
        case paidUsageUnits = "paid_usage_units"
        case frozenUsageUnits = "frozen_usage_units"
        case availableTalkifyPoints = "available_talkify_points"
        case frozenTalkifyPoints = "frozen_talkify_points"
        case currentSubscription = "current_subscription"
        case subscriptionActive = "subscription_active"
        case subscriptionExpiredAt = "subscription_expired_at"
        case planCode = "plan_code"
        case planVersion = "plan_version"
        case quotaPolicy = "quota_policy"
        case weekly
        case subscriptionCycle = "subscription_cycle"
        case currentFundingSource = "current_funding_source"
        case currentPeriodUsed = "current_period_used"
        case pointDiscountRate = "point_discount_rate"
        case canUse1080p = "can_use_1080p"
        case canRemoveWatermark = "can_remove_watermark"
        case canUsePriorityQueue = "can_use_priority_queue"
        case canUseCustomAspectRatio = "can_use_custom_aspect_ratio"
        case dailyFreeRemain = "daily_free_remain"
        case dailyDurationRemainSec = "daily_duration_remain_sec"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(Int.self, forKey: .userID)
        let legacyAvailablePoints = try container.decodeIfPresent(Int.self, forKey: .availablePoints) ?? 0
        let legacyFrozenPoints = try container.decodeIfPresent(Int.self, forKey: .frozenPoints) ?? 0
        paidUsageUnits = try container.decodeIfPresent(Int.self, forKey: .paidUsageUnits) ?? legacyAvailablePoints
        frozenUsageUnits = try container.decodeIfPresent(Int.self, forKey: .frozenUsageUnits) ?? legacyFrozenPoints
        availableTalkifyPoints = try container.decodeIfPresent(Double.self, forKey: .availableTalkifyPoints)
            ?? Double(paidUsageUnits) / 20_000
        frozenTalkifyPoints = try container.decodeIfPresent(Double.self, forKey: .frozenTalkifyPoints)
            ?? Double(frozenUsageUnits) / 20_000
        availablePoints = legacyAvailablePoints == 0 ? paidUsageUnits : legacyAvailablePoints
        frozenPoints = legacyFrozenPoints == 0 ? frozenUsageUnits : legacyFrozenPoints
        currentSubscription = try container.decodeIfPresent(String.self, forKey: .currentSubscription)
        subscriptionActive = try container.decodeIfPresent(Bool.self, forKey: .subscriptionActive) ?? false
        subscriptionExpiredAt = try container.decodeIfPresent(Int.self, forKey: .subscriptionExpiredAt)
        planCode = try container.decodeIfPresent(String.self, forKey: .planCode) ?? (subscriptionActive ? "pro" : "free")
        planVersion = try container.decodeIfPresent(Int.self, forKey: .planVersion) ?? 0
        quotaPolicy = try container.decodeIfPresent(String.self, forKey: .quotaPolicy) ?? "weekly_only"
        weekly = try container.decodeIfPresent(BillingQuotaPeriod.self, forKey: .weekly)
        subscriptionCycle = try container.decodeIfPresent(BillingQuotaPeriod.self, forKey: .subscriptionCycle)
        currentFundingSource = try container.decodeIfPresent(String.self, forKey: .currentFundingSource)
        currentPeriodUsed = try container.decodeIfPresent(Int.self, forKey: .currentPeriodUsed) ?? 0
        pointDiscountRate = try container.decodeIfPresent(Double.self, forKey: .pointDiscountRate) ?? 1
        canUse1080p = try container.decodeIfPresent(Bool.self, forKey: .canUse1080p) ?? false
        canRemoveWatermark = try container.decodeIfPresent(Bool.self, forKey: .canRemoveWatermark) ?? false
        canUsePriorityQueue = try container.decodeIfPresent(Bool.self, forKey: .canUsePriorityQueue) ?? false
        canUseCustomAspectRatio = try container.decodeIfPresent(Bool.self, forKey: .canUseCustomAspectRatio) ?? false
        dailyFreeRemain = try container.decodeIfPresent(Int.self, forKey: .dailyFreeRemain) ?? 0
        dailyDurationRemainSec = try container.decodeIfPresent(Int.self, forKey: .dailyDurationRemainSec) ?? 0
    }
}

public struct BillingEntitlements: Codable, Sendable {
    public let userID: Int
    public let subscriptionActive: Bool
    public let currentSubscription: String?
    public let subscriptionExpiredAt: Int?
    public let planCode: String
    public let planVersion: Int
    public let quotaPolicy: String
    public let weeklyIncludedUnits: Int
    public let subscriptionCycleIncludedUnits: Int
    public let benefitItems: [BillingBenefitItem]
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
        case planCode = "plan_code"
        case planVersion = "plan_version"
        case quotaPolicy = "quota_policy"
        case weeklyIncludedUnits = "weekly_included_units"
        case subscriptionCycleIncludedUnits = "subscription_cycle_included_units"
        case benefitItems = "benefit_items"
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(Int.self, forKey: .userID)
        subscriptionActive = try container.decodeIfPresent(Bool.self, forKey: .subscriptionActive) ?? false
        currentSubscription = try container.decodeIfPresent(String.self, forKey: .currentSubscription)
        subscriptionExpiredAt = try container.decodeIfPresent(Int.self, forKey: .subscriptionExpiredAt)
        planCode = try container.decodeIfPresent(String.self, forKey: .planCode) ?? (subscriptionActive ? "pro" : "free")
        planVersion = try container.decodeIfPresent(Int.self, forKey: .planVersion) ?? 0
        quotaPolicy = try container.decodeIfPresent(String.self, forKey: .quotaPolicy) ?? "weekly_only"
        weeklyIncludedUnits = try container.decodeIfPresent(Int.self, forKey: .weeklyIncludedUnits) ?? 0
        subscriptionCycleIncludedUnits = try container.decodeIfPresent(Int.self, forKey: .subscriptionCycleIncludedUnits) ?? 0
        benefitItems = try container.decodeIfPresent([BillingBenefitItem].self, forKey: .benefitItems) ?? []
        pointDiscountRate = try container.decodeIfPresent(Double.self, forKey: .pointDiscountRate) ?? 1
        canUse1080p = try container.decodeIfPresent(Bool.self, forKey: .canUse1080p) ?? false
        canRemoveWatermark = try container.decodeIfPresent(Bool.self, forKey: .canRemoveWatermark) ?? false
        canUsePriorityQueue = try container.decodeIfPresent(Bool.self, forKey: .canUsePriorityQueue) ?? false
        canUseCustomAspectRatio = try container.decodeIfPresent(Bool.self, forKey: .canUseCustomAspectRatio) ?? false
        dailyFreeLimit = try container.decodeIfPresent(Int.self, forKey: .dailyFreeLimit) ?? 0
        dailyFreeRemain = try container.decodeIfPresent(Int.self, forKey: .dailyFreeRemain) ?? 0
        dailyDurationLimitSec = try container.decodeIfPresent(Int.self, forKey: .dailyDurationLimitSec) ?? 0
        dailyDurationRemainSec = try container.decodeIfPresent(Int.self, forKey: .dailyDurationRemainSec) ?? 0
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
    public let availableTalkifyPoints: Double?

    enum CodingKeys: String, CodingKey {
        case orderNo = "order_no"
        case productType = "product_type"
        case subscriptionActive = "subscription_active"
        case availablePoints = "available_points"
        case availableTalkifyPoints = "available_talkify_points"
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
