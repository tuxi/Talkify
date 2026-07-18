//
//  DefaultInput.swift
//  FeatureAdminUI
//
//  Created by xiaoyuan on 2026/4/4.
//

import Foundation
import CoreKit

import Foundation
import CoreKit

// DefaultInput 不应该写死成一个固定表单。
// 它本质上应该和 InputSchema 联动
// InputSchema 决定“有哪些输入字段、字段类型、是否显示、是否必填、约束规则”
// DefaultInput 决定“这些字段默认填什么值”
// RenderConfig 决定“页面怎么摆、哪些区块显示”
// 工具页运行时根据这三者动态渲染
public struct AdminDefaultInputConfig: Codable, Sendable, Hashable {
    public var values: [String: JSONValue]

    public init(values: [String: JSONValue] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> JSONValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public mutating func removeValue(forKey key: String) {
        values.removeValue(forKey: key)
    }
}
