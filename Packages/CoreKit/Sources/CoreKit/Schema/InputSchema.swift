//
//  InputSchema.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/4.
//

import Foundation

public enum ToolInputFieldType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case prompt
    case image
    case video
    case number
    case text
    case select
    case mutilSelect
    case toggle
    case aspectRatio
    case duration
    case resolution
    case style
    case model
    case material

    public var id: String { rawValue }
    
    
}

public struct ToolInputFieldRule: Codable, Sendable, Hashable {
    public var minCount: Int?
    public var maxCount: Int?
    public var minValue: Double?
    public var maxValue: Double?
    public var allowedValues: [String]?
    public var maxLength: Int?

    public init(
        minCount: Int? = nil,
        maxCount: Int? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        allowedValues: [String]? = nil,
        maxLength: Int? = nil
    ) {
        self.minCount = minCount
        self.maxCount = maxCount
        self.minValue = minValue
        self.maxValue = maxValue
        self.allowedValues = allowedValues
        self.maxLength = maxLength
    }
}

public struct ToolInputFieldSchema: Codable, Sendable, Hashable, Identifiable {
    public var id = UUID() // 这里需要id，因在编辑页编辑filed的key时key会被改变，导致swiftui会重新渲染

    public var key: String
    public var title: String
    public var subtitle: String?
    public var type: ToolInputFieldType
    public var required: Bool
    public var visible: Bool
    public var sort: Int
    public var placeholder: String?
    public var rules: ToolInputFieldRule?

    public init(
        key: String,
        title: String,
        subtitle: String? = nil,
        type: ToolInputFieldType,
        required: Bool = false,
        visible: Bool = true,
        sort: Int = 0,
        placeholder: String? = nil,
        rules: ToolInputFieldRule? = nil
    ) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.required = required
        self.visible = visible
        self.sort = sort
        self.placeholder = placeholder
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case subtitle
        case type
        case required
        case visible
        case sort
        case placeholder
        case rules
    }
}

public extension ToolInputFieldSchema {
    static func makeDefault(for type: ToolInputFieldType) -> ToolInputFieldSchema {
        AdminBuiltinFieldTemplate.makeField(for: type)
    }
}

public struct ToolInputSchemaConfig: Codable, Sendable, Hashable {
    public var fields: [ToolInputFieldSchema]

    public init(fields: [ToolInputFieldSchema] = []) {
        self.fields = fields
    }

    public static func imageToVideoDefault() -> ToolInputSchemaConfig {
        .init(fields: [
            AdminBuiltinFieldTemplate.makeField(for: .image),
            AdminBuiltinFieldTemplate.makeField(for: .prompt),
            AdminBuiltinFieldTemplate.makeField(for: .model),
            AdminBuiltinFieldTemplate.makeField(for: .style),
            AdminBuiltinFieldTemplate.makeField(for: .duration),
            AdminBuiltinFieldTemplate.makeField(for: .resolution),
            AdminBuiltinFieldTemplate.makeField(for: .aspectRatio),
        ])
    }
    
    public static func textToImageDefault() -> ToolInputSchemaConfig {
        .init(fields: [
            AdminBuiltinFieldTemplate.makeField(for: .prompt),
            AdminBuiltinFieldTemplate.makeField(for: .model),
            AdminBuiltinFieldTemplate.makeField(for: .style),
            AdminBuiltinFieldTemplate.makeField(for: .select)
        ])
    }
}
