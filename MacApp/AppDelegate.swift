//
//  AppDelegate.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    // 设置菜单中的app 主题按钮
    @IBOutlet weak var darkModeItem: NSMenuItem!
    @IBOutlet weak var lightModeItem: NSMenuItem!
    @IBOutlet weak var systemModeItem: NSMenuItem!
    
    @UserDefault("system_mode", defaultValue: "system")
    var systemMode: String
    
    let prefs = Prefs()
    var prefsView: PrefsView?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        setStoredSystemMode()
        
        showLoginWindowForWindowController()
        
//        showMainWindowForContentView()
    }
    
    // 显示window scence
    // 通过storyboard 实现的登陆页面
    func showLoginWindowForWindowController() {
        
        let storyboard = NSStoryboard(name: "LoginWindowController", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier.init("LoginWindow")) as! LoginWindowController
        windowController.showWindow(self)
        window = windowController.window!
        // 设置关闭窗口时释放
        window.isReleasedWhenClosed = true
        window.center()
        window.setFrameAutosaveName("Login Window")
        window.title = "个人中心"
        window.makeKeyAndOrderFront(nil)
    }
    
    // 显示window 并设置contentViewController
    // 通过SwiftUI 实现的登陆页面
    func showLoginWindowForContentViewController() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: LoginView())
        // 设置关闭窗口时释放
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Login Window")
        window.title = "个人中心"
        window.makeKeyAndOrderFront(nil)
    }
    
    // 显示window 并设置contentView
    // App的主窗口
    func showMainWindowForContentView() {
        // 通过代码设置主window 否则 通过main.storyboard 设置
        let contentView = ContentView()

        // Create the window and set the content view.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "个人中心"
        window.contentView = NSHostingView(rootView: contentView.environmentObject(prefs))
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func setStoredSystemMode() {
        switch systemMode {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }
        
        showSelectedModeInMenu()
    }

    @IBAction func darkModeSelected(_ sender: Any) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        systemMode = "dark"
        showSelectedModeInMenu()
    }
    
    @IBAction func lightModeSelected(_ sender: Any) {
        NSApp.appearance = NSAppearance(named: .aqua)
        systemMode = "light"
        showSelectedModeInMenu()
    }
    @IBAction func systemModeSelected(_ sender: Any) {
        NSApp.appearance = nil
        systemMode = "system"
        showSelectedModeInMenu()
    }
    
    func showSelectedModeInMenu() {
        switch systemMode {
        case "dark":
            darkModeItem.state = .on
            lightModeItem.state = .off
            systemModeItem.state = .off
        case "light":
            darkModeItem.state = .off
            lightModeItem.state = .on
            systemModeItem.state = .off
        default:
            darkModeItem.state = .off
            lightModeItem.state = .off
            systemModeItem.state = .on
        }
    }
}

