//
//  SettingsSection.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import Foundation
import CoreKit

enum SettingsSection: String, CaseIterable, Identifiable {
    enum Group: CaseIterable { case personal, integrations, development
        var title: String {
            switch self {
            case .personal: TalkifyLocalized.string("settings.group.personal")
            case .integrations: TalkifyLocalized.string("settings.group.integrations")
            case .development: TalkifyLocalized.string("settings.group.development")
            }
        }
    }

    case general, profile, appearance, voice, configuration, personalization, shortcuts, usage, account
    case appSnapshots, plugins, browser, computerControl, hooks, connections, git, environment

    var id: String { rawValue }
    var group: Group {
        switch self {
        case .general, .profile, .appearance, .voice, .configuration, .personalization, .shortcuts, .usage, .account: .personal
        case .appSnapshots, .plugins, .browser, .computerControl: .integrations
        case .hooks, .connections, .git, .environment: .development
        }
    }
    var title: String {
        switch self {
        case .general: TalkifyLocalized.string("settings.item.general")
        case .profile: TalkifyLocalized.string("settings.item.profile")
        case .appearance: TalkifyLocalized.string("settings.item.appearance")
        case .voice: TalkifyLocalized.string("settings.item.voice")
        case .configuration: TalkifyLocalized.string("settings.item.configuration")
        case .personalization: TalkifyLocalized.string("settings.item.personalization")
        case .shortcuts: TalkifyLocalized.string("settings.item.shortcuts")
        case .usage: TalkifyLocalized.string("settings.item.usage")
        case .account: TalkifyLocalized.string("settings.item.account")
        case .appSnapshots: TalkifyLocalized.string("settings.item.app_snapshots")
        case .plugins: TalkifyLocalized.string("settings.item.plugins")
        case .browser: TalkifyLocalized.string("settings.item.browser")
        case .computerControl: TalkifyLocalized.string("settings.item.computer_control")
        case .hooks: TalkifyLocalized.string("settings.item.hooks")
        case .connections: TalkifyLocalized.string("settings.item.connections")
        case .git: TalkifyLocalized.string("settings.item.git")
        case .environment: TalkifyLocalized.string("settings.item.environment")
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"; case .profile: "person.crop.circle"; case .appearance: "sun.max"; case .voice: "mic"; case .configuration: "shield"; case .personalization: "dial.medium"; case .shortcuts: "command"; case .usage: "chart.bar"; case .account: "person.badge.key"; case .appSnapshots: "viewfinder"; case .plugins: "puzzlepiece"; case .browser: "rectangle"; case .computerControl: "cursorarrow.and.square.on.square.dashed"; case .hooks: "anchor"; case .connections: "globe"; case .git: "point.3.connected.trianglepath.dotted"; case .environment: "laptopcomputer"
        }
    }
}
