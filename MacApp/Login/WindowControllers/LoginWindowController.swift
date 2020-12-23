//
//  LoginWindowController.swift
//  QQ
//
//  Created by mac on 2017/12/16.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa
import SwiftUI


class LoginWindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()

        //使窗口移动
        window?.isMovableByWindowBackground = true
        //设置窗口背景颜色
        window?.backgroundColor = .white
        
    }

}
