//
//  SettingsSection.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import Foundation
import CoreKit

enum SettingsSection: String, CaseIterable, Identifiable {
    enum Group: CaseIterable { case personal, integrations
        var title: String {
            switch self {
            case .personal: TalkifyLocalized.string("settings.group.personal")
            case .integrations: TalkifyLocalized.string("settings.group.integrations")
            }
        }
    }
    case profile, usage, account
    case servers, providers, models, permissions, settings
    case support, about

    var id: String { rawValue }
    var group: Group {
        switch self {
        case .profile, .usage, .account: .personal
        case .servers, .providers, .models, .permissions, .settings: .integrations
        case .support, .about: .personal
        }
    }
    var title: String {
        switch self {
        case .profile: TalkifyLocalized.string("settings.item.profile")
        case .usage: TalkifyLocalized.string("settings.item.usage")
        case .account: TalkifyLocalized.string("settings.item.account")
        case .servers: "服务器"
        case .providers: "提供商"
        case .models: "模型"
        case .permissions: "权限"
        case .settings: "配置"
        case .support: TalkifyLocalized.string("settings.item.support")
        case .about: TalkifyLocalized.string("settings.item.about")
        }
    }
    var icon: String {
        switch self {
        case .profile: "person.crop.circle"
        case .usage: "chart.bar"
        case .account: "person.badge.key"
        case .servers: "server.rack"
        case .providers: "cpu"
        case .models: "sparkles"
        case .permissions: "shield"
        case .settings: "gearshape.2"
        case .support: "questionmark.bubble"
        case .about: "info.circle"
        }
    }
}
