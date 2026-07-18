import Foundation

public struct UserProfile: Codable, Sendable {
    public let userId: Int
    public let username: String
    public let nickname: String?
    public let avatarURL: String?
    public let phoneMasked: String?
    public let hasPhone: Bool
    public let hasApple: Bool
    public let isActive: Bool
    public let registerSource: String?
    public let createdAt: Int
    public let updatedAt: Int
    public let subscriptionActive: Bool
    public let currentSubscription: String?
    public let subscriptionExpiredAt: Int?
    public let availablePoints: Int
    public let frozenPoints: Int
    public let canUse1080p: Bool
    public let canRemoveWatermark: Bool
    public let canUsePriorityQueue: Bool
    public let canUseCustomAspectRatio: Bool
    public let pointDiscountRate: Double
    
    public var avatarDisplayURL: URL? {
        guard let avatarURL, !avatarURL.isEmpty else { return nil }
        
        // 版本号 = userId + createdAt（永远唯一、永远不变、更新就变）
        return URL(string: "\(avatarURL)?v=\(updatedAt)")
    }
    
    public init(
        userId: Int,
        username: String,
        nickname: String,
        avatarURL: String?,
        phoneMasked: String?,
        hasPhone: Bool,
        hasApple: Bool,
        isActive: Bool,
        registerSource: String?,
        createdAt: Int,
        updatedAt: Int,
        subscriptionActive: Bool,
        currentSubscription: String?,
        subscriptionExpiredAt: Int?,
        availablePoints: Int,
        frozenPoints: Int,
        canUse1080p: Bool,
        canRemoveWatermark: Bool,
        canUsePriorityQueue: Bool,
        canUseCustomAspectRatio: Bool,
        pointDiscountRate: Double
    ) {
        self.userId = userId
        self.username = username
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.phoneMasked = phoneMasked
        self.hasPhone = hasPhone
        self.hasApple = hasApple
        self.isActive = isActive
        self.registerSource = registerSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.subscriptionActive = subscriptionActive
        self.currentSubscription = currentSubscription
        self.subscriptionExpiredAt = subscriptionExpiredAt
        self.availablePoints = availablePoints
        self.frozenPoints = frozenPoints
        self.canUse1080p = canUse1080p
        self.canRemoveWatermark = canRemoveWatermark
        self.canUsePriorityQueue = canUsePriorityQueue
        self.canUseCustomAspectRatio = canUseCustomAspectRatio
        self.pointDiscountRate = pointDiscountRate
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case nickname
        case avatarURL = "avatar_url"
        case phoneMasked = "phone_masked"
        case hasPhone = "has_phone"
        case hasApple = "has_apple"
        case isActive = "is_active"
        case registerSource = "register_source"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case subscriptionActive = "subscription_active"
        case currentSubscription = "current_subscription"
        case subscriptionExpiredAt = "subscription_expired_at"
        case availablePoints = "available_points"
        case frozenPoints = "frozen_points"
        case canUse1080p = "can_use_1080p"
        case canRemoveWatermark = "can_remove_watermark"
        case canUsePriorityQueue = "can_use_priority_queue"
        case canUseCustomAspectRatio = "can_use_custom_aspect_ratio"
        case pointDiscountRate = "point_discount_rate"
    }
}
