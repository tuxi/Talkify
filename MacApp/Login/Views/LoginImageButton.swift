//
//  LoginImageButton.swift
//  QQ
//
//  Created by mac on 2017/12/17.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa

class LoginImageButton: NSButton {
    //当鼠标移进个人图标里是的颜色
    let mouseEnteredColor = NSColor(red:0.44, green:0.84, blue:0.95, alpha:1.00)
    //当鼠标不在个人图像时的边框颜色
    let defaultColor = NSColor(red:0.72, green:0.75, blue:0.77, alpha:1.00)
    //边框宽度
    let borderWidth: CGFloat = 1
    //当鼠标移动斤图像内边框的宽度
    let mouseEnteredWidth: CGFloat = 2
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        //将正方形转换成圆形
        layer?.cornerRadius = dirtyRect.width / 2
        //设置图片的scalling
        imageScaling = .scaleAxesIndependently
        
        let trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited,.activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        changeColor(defaultColor, with: borderWidth)
    }
    override func mouseEntered(with event: NSEvent) {
        changeColor(mouseEnteredColor, with: mouseEnteredWidth)
    }
    override func mouseExited(with event: NSEvent) {
        changeColor(defaultColor, with: borderWidth)
    }
    func changeColor(_ color: NSColor, with width: CGFloat) {
        layer?.borderColor = color.cgColor
        layer?.borderWidth = width
    }
    
}
