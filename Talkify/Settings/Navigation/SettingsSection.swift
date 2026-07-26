//
//  SettingsSection.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    enum Group: CaseIterable { case personal, integrations, development
        var title: String { switch self { case .personal: "个人"; case .integrations: "集成"; case .development: "编码" } }
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
        case .general: "常规"; case .profile: "个人资料"; case .appearance: "外观"; case .voice: "语音"; case .configuration: "配置"; case .personalization: "个性化"; case .shortcuts: "键盘快捷键"; case .usage: "使用情况和计费"; case .account: "账户"; case .appSnapshots: "应用快照"; case .plugins: "插件"; case .browser: "浏览器"; case .computerControl: "电脑操控"; case .hooks: "钩子"; case .connections: "连接"; case .git: "Git"; case .environment: "环境"
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"; case .profile: "person.crop.circle"; case .appearance: "sun.max"; case .voice: "mic"; case .configuration: "shield"; case .personalization: "dial.medium"; case .shortcuts: "command"; case .usage: "chart.bar"; case .account: "person.badge.key"; case .appSnapshots: "viewfinder"; case .plugins: "puzzlepiece"; case .browser: "rectangle"; case .computerControl: "cursorarrow.and.square.on.square.dashed"; case .hooks: "anchor"; case .connections: "globe"; case .git: "point.3.connected.trianglepath.dotted"; case .environment: "laptopcomputer"
        }
    }
}
