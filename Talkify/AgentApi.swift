//
//  AgentApi.swift
//  CodeAgent
//
//  Created by xiaoyuan on 2026/7/12.
//

import Foundation
import CoreKit
import Alamofire

enum AgentApi {
    case usage
    case models
    case resetCards
    case redeemResetCard(id: String, idempotencyKey: String)
}

extension AgentApi: ApiEndpoint {
    var path: String {
        switch self {
        case .usage:
            return "agent/usage"
        case .models:
            return "agent/models"
        case .resetCards:
            return "agent/quota/reset-cards"
        case .redeemResetCard(let id, _):
            return "agent/quota/reset-cards/\(id)/redeem"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .usage, .models, .resetCards:
            return .get
        case .redeemResetCard:
            return .post
        }
    }
    
    var parameters: [String : any Sendable] {
        switch self {
        case .redeemResetCard(_, let idempotencyKey):
            return ["idempotency_key": idempotencyKey]
        default:
            return [:]
        }
    }
    
    var encoding: ApiParameterEncoding {
        .url
    }
    
}
