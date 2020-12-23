//
//  LoginPasswordTextField.swift
//  QQ
//
//  Created by mac on 2017/12/19.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa

class LoginPasswordTextField: NSSecureTextField, NSTextFieldDelegate {
    private static let phString: String = "输入密码"
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        self.delegate = self
        
    }
    override func mouseDown(with event: NSEvent) {
        self.currentEditor()?.selectAll(nil)
        self.placeholderString = ""
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        self.placeholderString = LoginPasswordTextField.phString
    }
}
