//
//  NSWindow+Utils.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import SwiftUI

extension NSWindow {
    
    static func createStandardWindow(WithTitle title: String,
                                     width: CGFloat = 800,
                                     height: CGFloat = 600) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.center()
        window.title = title
        return window
    }
}
