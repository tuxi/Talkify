//
//  StatusButton.swift
//  QQ
//
//  Created by mac on 2017/12/26.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa

class StatusButton: NSButton {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.cornerRadius = dirtyRect.width / 2
        self.isBordered = false
        imageScaling = .scaleAxesIndependently
    }
    
}
