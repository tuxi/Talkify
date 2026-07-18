//
//  JSONValue.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/29.
//

import Foundation

public enum JSONValue: Sendable, Codable, Hashable {
    case string(String)
    case number(Double) // 统一数值类型
    case integer(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    // MARK: - Initializers
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        // 优先尝试 decode 为 Double，因为 JSON 中数值都是 Number
        else if let v =  try? container.decode(Int.self) { self = .integer(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .integer(let v): try container.encode(v)
        case .number(let v): try container.encode(v) // 自动处理整数或浮点
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - 便捷取值 (The "SwiftyJSON" Style)
public extension JSONValue {
    
    /// 支持 json["key"] 或 json[0] 的链式访问
    subscript(key: String) -> JSONValue {
        if case .object(let dict) = self { return dict[key] ?? .null }
        return .null
    }
    
    subscript(index: Int) -> JSONValue {
        if case .array(let array) = self, array.indices.contains(index) { return array[index] }
        return .null
    }

    // 基础类型转换，带默认值以防 Crash
    var stringValue: String {
        if case .string(let v) = self { return v }
        if case .number(let v) = self { return "\(v)" }
        if case .integer(let v) = self {
            return "\(v)"
        }
        if case .bool(let v) = self { return "\(v)" }
        return ""
    }

    var intValue: Int {
        if case .integer(let int) = self {
            return int
        }
        if case .number(let v) = self { return Int(v) }
        if case .string(let v) = self { return Int(v) ?? 0 }
        return 0
    }

    var boolValue: Bool {
        if case .bool(let v) = self { return v }
        if case .integer(let v) = self {
            return v != 0
        }
        if case .number(let v) = self { return v != 0 }
        if case .string(let v) = self { return ["true", "y", "1"].contains(v.lowercased()) }
        return false
    }

    var doubleValue: Double {
        if case .number(let v) = self { return v }
        if case .integer(let int) = self {
            return Double(int)
        }
        if case .string(let v) = self { return Double(v) ?? 0.0 }
        return 0.0
    }

    // 返回可选类型，用于判断是否存在
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var int: Int? { if case .integer(let v) = self { return v }; return nil }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
}

// MARK: - 字面量支持 (保持原样，非常棒)
extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .integer(v) }
    public init(floatLiteral v: Double) { self = .number(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
}

public extension JSONValue {
    var asSendable: Sendable {
        switch self {
        case .string(let value):
            return value
        case .integer(let v): return v
        case .number(let v): return v // Double 已经是 Sendable
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.asSendable }
        case .array(let value):
            return value.map { $0.asSendable }
        case .null:
            return NSNull()
        }
    }
}

public extension JSONValue {
    var asJSONObject: Any {
        switch self {
        case .string(let value):
            return value
        case .integer(let value): return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.asJSONObject }
        case .array(let value):
            return value.map { $0.asJSONObject }
        case .null:
            return NSNull()
        }
    }
    
    var description: String? {
        JSONValue.prettyString(from: self)
    }
    
    var prettyJSONString: String? {
        JSONValue.prettyString(from: self)
    }

    static func prettyString(from value: JSONValue) -> String? {
        let object = value.asJSONObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

// MARK: - Factory
public extension JSONValue {
    static func from(_ value: Any) -> JSONValue? {
        self.from(any: value)
    }
    static func from(any value: Any) -> JSONValue? {
        switch value {
        case let value as String:
            return .string(value)
        case let value as Int:
            return .number(Double(value))
        case let value as Int64:
            return .number(Double(value))
        case let value as Double:
            return .number(value)
        case let value as Bool:
            return .bool(value)
        case _ as NSNull:
            return .null
        case let array as [Any]:
            return .array(array.compactMap { JSONValue.from(any: $0) })
        case let dict as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, value) in dict {
                result[key] = JSONValue.from(any: value)
            }
            return .object(result)
        default:
            return nil
        }
    }
    
    func toAnyObject() -> Any? {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .array(let items):
            return items.compactMap { $0.toAnyObject() }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = value.toAnyObject()
            }
            return result
        }
    }
}
