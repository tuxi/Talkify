//
//  Clipboard.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/29.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct Clipboard {
   public static func copy(_ text: String?) {
        guard let text = text else { return }
        
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents() // 必须先清除，才能成为当前内容的拥有者
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
