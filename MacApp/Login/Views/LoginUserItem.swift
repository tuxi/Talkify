//
//  LoginUserItem.swift
//  QQ
//
//  Created by mac on 2017/12/25.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa
protocol LoginUserItemDelegate {
    func loginUserItem(_ item: LoginUserItem, with sender: NSButton)
}
class LoginUserItem: NSCollectionViewItem {
    //删除按钮
    @IBOutlet weak var closeButton: NSButton!
    
    @IBOutlet weak var imageButton: LoginImageButton!
    
    var delegate: LoginUserItemDelegate?
    
    var model: LoginUserItemModel! {
        didSet {
            imageButton.image = NSImage(named: NSImage.Name(model.name))
        }
    }
    typealias UserBlcok = (_ sender: Any) -> Void
    var block: UserBlcok?
    override func viewDidLoad() {
        super.viewDidLoad()
        //添加TrackingArea
        let trackingArea = NSTrackingArea(rect: view.bounds, options: [.activeInActiveApp,.mouseEnteredAndExited], owner: self, userInfo: nil)
        view.addTrackingArea(trackingArea)
    }
    @IBAction func handleUserButton(_ sender: Any) {
        if let b = block {
            b(sender)
        }
    }
    //删除当前item
    @IBAction func handleDeleteButton(_ sender: Any) {
        if let delegate = delegate {
            delegate.loginUserItem(self, with: sender as! NSButton)
        }
    }
    //鼠标进入此视图时经过的方法
    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }
    //鼠标移出此视图时经过的方法
    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }
    
}
