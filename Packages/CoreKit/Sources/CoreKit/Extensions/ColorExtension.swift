//
//  ColorExtension.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/1.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#endif

extension Color {

    /// 将 Color 转换为 Hex 字符串 (格式: ARGB)
    public func toHex() -> String? {
        // 1. 将 SwiftUI Color 转为平台原生颜色
        let platformColor = PlatformColor(self)
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        #if os(iOS) || os(tvOS) || os(watchOS)
        // iOS 直接获取组件
        guard platformColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #elseif os(macOS)
        // macOS 必须先确保在 RGB 颜色空间，否则访问组件可能崩溃（例如系统色）
        guard let rgbColor = platformColor.usingColorSpace(.deviceRGB) else { return nil }
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        
        return String(format: "%02X%02X%02X%02X",
                      Int(a * 255),
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255))
    }
}

extension Color: Codable {
    
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    private struct CodableColor: Codable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double
    }

    public func encode(to encoder: Encoder) throws {
        let platformColor = PlatformColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        #if os(iOS) || os(tvOS)
        platformColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif os(macOS)
        // 同样处理 macOS 颜色空间问题
        if let rgbColor = platformColor.usingColorSpace(.deviceRGB) {
            rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        #endif

        let codableColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
        var container = encoder.singleValueContainer()
        try container.encode(codableColor)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let codableColor = try container.decode(CodableColor.self)
        self.init(
            .sRGB,
            red: codableColor.red,
            green: codableColor.green,
            blue: codableColor.blue,
            opacity: codableColor.opacity
        )
    }
}
