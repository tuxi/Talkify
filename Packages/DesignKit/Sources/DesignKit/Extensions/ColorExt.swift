//
//   ColorExt.swift
//   DesignKit
//
//   Created by xiaoyuan on 2026/3/29.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

extension Color {
    /// 适配 iOS 和 macOS 的系统主背景色
    /// macOS: windowBackgroundColor (窗口背景)
    /// iOS: systemBackground (白色/黑色)
    public static var systemBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    
    /// 容器或控件的背景色
    /// macOS: controlBackgroundColor (输入框、列表背景)
    /// iOS: secondarySystemBackground (浅灰色层级)
    public static var controlBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
    
    public static var adaptiveGray3: Color {
#if os(macOS)
        // tertiaryLabelColor 在 macOS 上提供了非常接近的中灰度感
        return Color(NSColor.tertiaryLabelColor)
#else
        return Color(uiColor: .systemGray3)
#endif
    }
    
   public static var platformBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .systemGray6)
        #endif
    }
    /// 页面底层的背景色（通常用于滚动视图背后的底色）
    /// macOS: underPageBackgroundColor
    /// iOS: systemGroupedBackground (分组列表底色)
    public static var underPageBackground: Color {
        #if os(macOS)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(UIColor.systemGroupedBackground)
        #endif
    }
    
    /// 窗口背景色（显式别名，方便 macOS 开发习惯）
    public static var windowBackground: Color {
        systemBackground
    }
}

extension Color {
    /// 通用跨平台 Hex 初始化（支持 #、不带#、RGB、ARGB、自定义 alpha）
    /// - Parameters:
    ///   - hex: 色值 #8E54E9 / 8E54E9 / FFFFFF
    ///   - alpha: 透明度 0~1，会覆盖 hex 中的 alpha
    public init(hex: String, alpha: Double = 1.0) {
        // 清理字符串：去掉 #、0x、空格
        let cleanHex = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "0x", with: "")
        
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        
        let r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (F00)
            r = (rgbValue >> 8) * 17
            g = (rgbValue >> 4 & 0xF) * 17
            b = (rgbValue & 0xF) * 17
        case 6: // RGB (FF0000)
            r = (rgbValue >> 16) & 0xFF
            g = (rgbValue >> 8) & 0xFF
            b = rgbValue & 0xFF
        case 8: // ARGB (FFFF0000)
            r = (rgbValue >> 16) & 0xFF
            g = (rgbValue >> 8) & 0xFF
            b = rgbValue & 0xFF
        default:
            r = 0
            g = 0
            b = 0
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: alpha
        )
    }
}
