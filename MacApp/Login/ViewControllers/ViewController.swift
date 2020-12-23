//
//  ViewController.swift
//  QQ
//
//  Created by mac on 2017/12/16.
//  Copyright © 2017年 shibiao. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {
    let statusButtonHeight: CGFloat = 15
    private static let sound = NSSound(named: NSSound.Name.init("login_tip.mp3"))
    @IBOutlet weak var accountTextField: LoginAccountTextField!
    @IBOutlet weak var passwordTextField: LoginPasswordTextField!

    @IBOutlet weak var loginButton: NSButton!
    
    @IBOutlet weak var qrViewButton: NSButton!
    //显示或者隐藏子窗口按钮
    @IBOutlet weak var showOrhideWindowBtn: NSButton!
    //扫描二维码登录视图
    @IBOutlet var qrView: NSView!
    //账号collectionView
    @IBOutlet weak var collectionView: NSCollectionView!
    //用户数据
    var usersData = Array<LoginUserItemModel>()
    var itemRect: NSRect?
    lazy var transitionItem: LoginImageButton = {
        let button = LoginImageButton()
        button.target = self
        button.action = #selector(handleTransition(button:))
        button.isBordered = false
        return button
    }()
    lazy var settingWindow: NSWindow = {
        let tempWindow = NSWindow(contentRect: NSMakeRect((self.view.window?.frame.origin.x)!, (self.view.window?.frame.origin.y)!+99, (self.view.window?.frame.size.width)!, 78), styleMask: [.titled], backing: NSWindow.BackingStoreType.buffered, defer: true)
        tempWindow.contentViewController = NSStoryboard(name: NSStoryboard.Name.init("LoginWindowController"), bundle: nil).instantiateController(withIdentifier: NSStoryboard.SceneIdentifier.init("settingVC")) as! SettingViewController
        self.view.window?.animator().addChildWindow(tempWindow, ordered: .below)
        //设置子窗口的颜色
        tempWindow.backgroundColor = .white
        
        return tempWindow
    }()
    //状态按钮
    lazy var statusBtn: StatusButton = {
        let tmpBtn = StatusButton()
        tmpBtn.image = #imageLiteral(resourceName: "online_status")
        tmpBtn.translatesAutoresizingMaskIntoConstraints = false
        tmpBtn.isBordered = false
        tmpBtn.target = self
        tmpBtn.action = #selector(handleStatus(_:))
        return tmpBtn
    }()
    
    deinit {
        print("ViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loginButton.contentTintColor = NSColor.blue
        
        //赋值数据
        for i in 1...5 {
            usersData.append(LoginUserItemModel(name: "2_0\(i)" ))
        }
        
        //将二维码视图界面背景改成白色
        qrView.wantsLayer = true
        qrView.layer?.backgroundColor = NSColor.white.cgColor
        //注册Cell
        collectionView.register(NSNib.init(nibNamed: NSNib.Name.init("LoginUserItem"), bundle: nil), forItemWithIdentifier: NSUserInterfaceItemIdentifier.init("LoginUserItem"))
    }
    // 检测登录按钮的状态
    @objc func detectLoginButtonState() {
        if !self.accountTextField.stringValue.isEmpty && !self.passwordTextField.stringValue.isEmpty {
            self.loginButton.isEnabled = true
        }else {
            self.loginButton.isEnabled = false
        }
    }
    override func viewWillAppear() {
        super.viewWillAppear()
        //设置运行后所显示的个人图像
        let indexPath = IndexPath(item: 0, section: 0)
        let firstItem = collectionView.item(at: indexPath)
        itemRect = self.view.convert((firstItem?.view.frame)!, from: collectionView)
        transitionItem.frame = itemRect!
        transitionItem.image = NSImage(named: NSImage.Name.init(usersData[indexPath.item].name))
        collectionView.isHidden = true
        self.view.addSubview(transitionItem)
        var tmpFrame = NSMakeRect(view.frame.width/2, 0, 100, 100)
        tmpFrame = view.convert(tmpFrame, to: collectionView)
        transitionItem.frame = tmpFrame
        transitionItem.imageScaling = .scaleAxesIndependently
        self.addStatsButton()
        //检测登录按钮的状态
        detectLoginButtonState()
        
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillMoveNotification), name: NSWindow.willMoveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(detectLoginButtonState), name: NSText.didChangeNotification, object: nil)
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        NotificationCenter.default.removeObserver(self)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        accountTextField.becomeFirstResponder()
    }
    
    @objc func windowWillMoveNotification() {
        if self.showOrhideWindowBtn.state == .off {
            guard (self.view.window != nil) else {
                return
            }
            self.settingWindow.animator().setFrame(NSMakeRect((self.view.window?.frame.origin.x)!, (self.view.window?.frame.origin.y)!+99, (self.view.window?.frame.size.width)!, 1), display: true)
            self.view.window?.animator().addChildWindow(self.settingWindow, ordered: .below)
        }
    }
    
    //状态按钮切换方法
    @objc func handleStatus(_ button: NSButton) {
        if button.image == #imageLiteral(resourceName: "online_status") {
            button.image = #imageLiteral(resourceName: "hide_status")
        }else {
            button.image = #imageLiteral(resourceName: "online_status")
        }
    }
    @IBAction func handleCloseButton(_ sender: Any) {
        NSApp.terminate(sender)
        //        NSApp 等于 NSApplication.shared
        //        NSApplication.shared.terminate(sender)
    }
    //点击进入扫描二维码界面
    @IBAction func handleQREvent(_ sender: NSButton) {
        qrViewButton.isHidden = true
        self.view.addSubview(self.qrView)
    }
    //返回登录界面
    @IBAction func accountLogin(_ sender: Any) {
        qrViewButton.isHidden = false
        self.qrView.removeFromSuperview()
    }
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "pushToMain" {
            view.window?.close()
        }
    }
    
    // 点击登陆
    @IBAction func clickLoginBtn(_ sender: Any) {
        (NSApp.delegate as! AppDelegate).showMainWindowForContentView()
        // 关闭现在的登陆窗口
        self.view.window?.orderOut(self)
    }
    
    @IBAction func showOrHideSubWindow(_ sender: NSButton) {
        //每点击此方法播放一下声音
        ViewController.sound?.play()
        NSAnimationContext.runAnimationGroup({ (context) in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
            if sender.state == .on {
                self.settingWindow.animator().setFrame(NSMakeRect((self.view.window?.frame.origin.x)!, (self.view.window?.frame.origin.y)!-78, (self.view.window?.frame.size.width)!, 100), display: true)
                self.view.window?.animator().addChildWindow(self.settingWindow, ordered: .below)
            }else {
                
                view.window?.removeChildWindow(self.settingWindow)
                self.settingWindow.animator().setFrame(NSMakeRect((self.view.window?.frame.origin.x)!, (self.view.window?.frame.origin.y)!+22, (self.view.window?.frame.size.width)!, 0), display: false)
            }
        }, completionHandler: nil)
        
    }
    
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    //过渡按钮button点击事件
    @objc func handleTransition(button: LoginImageButton) {
        self.statusBtn.isHidden = true
        NSAnimationContext.runAnimationGroup({ (context) in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
            self.transitionItem.animator().frame = itemRect!
        }) {
            self.collectionView.isHidden = false
            self.transitionItem.removeFromSuperview()
        }
    }
    //获取collectionView点击事件对应item和其indexPath
    func handleItem(_ item: LoginUserItem, with indexPath: IndexPath) {
        itemRect = view.convert(item.view.frame, from: collectionView)
        transitionItem.frame = itemRect!
        self.transitionItem.image = NSImage(named: NSImage.Name(usersData[indexPath.item].name))
        collectionView.isHidden = true
        view.addSubview(transitionItem)
        
        NSAnimationContext.runAnimationGroup({ (context) in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
            var tmpFrame = NSMakeRect(self.view.frame.width/2, 0, 100, 100)
            tmpFrame = view.convert(tmpFrame, to: self.collectionView)
            self.transitionItem.animator().frame = tmpFrame
        }, completionHandler:{
            self.addStatsButton()
        })
    }
    func addStatsButton() {
        self.statusBtn.isHidden = false
        self.view.addSubview(self.statusBtn)
        self.statusBtn.bottomAnchor.constraint(equalTo: self.transitionItem.bottomAnchor, constant: self.statusButtonHeight/2).isActive = true
        self.statusBtn.heightAnchor.constraint(equalToConstant: self.statusButtonHeight).isActive = true
        self.statusBtn.widthAnchor.constraint(equalToConstant: self.statusButtonHeight).isActive = true
        self.statusBtn.centerXAnchor.constraint(equalTo: self.transitionItem.centerXAnchor).isActive = true
    }
}

//FIXME: NSCollectionViewDataSource
extension ViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return usersData.count
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier.init("LoginUserItem"), for: indexPath) as! LoginUserItem
        //模型赋值
        item.model = usersData[indexPath.item]
        //block传值
        item.block = { (sender) -> Void in
            self.handleItem(item, with: indexPath)
        }
        //代理协议
        item.delegate = self
        return item
    }
    
}
//MARK: LoginUserItemDelegate
extension ViewController: LoginUserItemDelegate {
    func loginUserItem(_ item: LoginUserItem, with sender: NSButton) {
        let indexPath = collectionView.indexPath(for: item)
        collectionView.deleteItems(at: [indexPath!])
        usersData.remove(at: (indexPath?.item)!)
        collectionView.reloadData()
    }
    
    
}
