//
//  Models.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import Foundation

struct SidebarSectionItem: Identifiable, Codable {
    var id = UUID()
    let title: String
    let icon: String
}

// 侧边栏的每一组
struct SidebarSection: Identifiable, Codable {
    
    var id = UUID()
    let title: String
    let icon: String
    let items: [SidebarSectionItem]
    
}

struct MainSection: Hashable, Codable, Identifiable {
    var id = UUID()
    let name: String
}

struct MyCourse: Hashable, Codable, Identifiable {
    var id = UUID()
    let name: String
    let content: String
    // 学习进度
    let progress: Double
}
