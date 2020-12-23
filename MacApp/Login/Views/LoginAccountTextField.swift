//
//  LoginAccountTextField.swift
//  QQ
//
//  Created by mac on 2017/12/19.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa

class LoginAccountTextField: NSTextField, NSTextFieldDelegate {
    private static let phString: String = "输入账号"
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        self.delegate = self
        
    }
    override func mouseDown(with event: NSEvent) {
        self.currentEditor()?.selectAll(nil)
        self.placeholderString = ""
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        
    }
    
    func controlTextDidChange(_ obj: Notification) {
        
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        self.placeholderString = LoginAccountTextField.phString
    }
}
