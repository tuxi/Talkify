//
//  BillingPublicSubscriptionPage.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/19.
//

import Foundation

public struct BillingPublicSubscriptionPage: Codable, Sendable {
    public let title: String
    public let subtitle: String?
    public let recommendedSubscriptionProductCode: String?
    public let renewHintText: String?
    public let restoreButtonTitle: String?
    public let termsURL: String?
    public let privacyURL: String?
    public let products: [BillingProduct]

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case recommendedSubscriptionProductCode = "recommended_subscription_product_code"
        case renewHintText = "renew_hint_text"
        case restoreButtonTitle = "restore_button_title"
        case termsURL = "terms_url"
        case privacyURL = "privacy_url"
        case products
    }

    public init(
        title: String,
        subtitle: String?,
        recommendedSubscriptionProductCode: String?,
        renewHintText: String?,
        restoreButtonTitle: String?,
        termsURL: String?,
        privacyURL: String?,
        products: [BillingProduct]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.recommendedSubscriptionProductCode = recommendedSubscriptionProductCode
        self.renewHintText = renewHintText
        self.restoreButtonTitle = restoreButtonTitle
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.products = products
    }
}
