//
//  AdminJSONCodec.swift
//  FeatureAdminUI
//
//  Created by xiaoyuan on 2026/4/4.
//

import Foundation
import CoreKit

public enum JSONCodec {
    public static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue?, fallback: T) -> T {
        guard let value else { return fallback }
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return fallback
        }
    }
    
    public static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public static func encode<T: Encodable>(_ value: T) -> JSONValue? {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return nil
        }
    }
    
    public static func decode(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            return JSONValue.from(any: object)
        } catch {
            return nil
        }
    }

    public static func prettyString(from value: JSONValue) -> String? {
        guard let any = value.toAnyObject() else { return nil }
        guard JSONSerialization.isValidJSONObject(any) else {
            if case .string(let text) = value {
                return text
            }
            return value.description
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return value.description
        }
    }
}
