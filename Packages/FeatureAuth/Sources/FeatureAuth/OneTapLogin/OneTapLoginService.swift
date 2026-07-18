//
//  OneTapLoginService.swift
//  FeatureAuth
//

import Foundation
import SwiftUI
#if canImport(ATAuthSDK_D)
import ATAuthSDK_D
import UIKit
#endif
import CoreKit

public enum OneTapLoginError: LocalizedError {
    case sdkNotAvailable
    case initializeFailed(String)
    case envNotAvailable(String)
    case tokenFailed(String)
    case userCancelled
    case userSwitchToOtherLogin

    public var errorDescription: String? {
        switch self {
        case .sdkNotAvailable:
            return "一键登录SDK不可用"
        case .initializeFailed(let msg):
            return "SDK初始化失败: \(msg)"
        case .envNotAvailable(let msg):
            return "当前环境不支持一键登录: \(msg)"
        case .tokenFailed(let msg):
            return "获取Token失败: \(msg)"
        case .userCancelled:
            return "用户取消登录"
        case .userSwitchToOtherLogin:
            return "用户选择其他登录方式"
        }
    }
}

@MainActor
public final class OneTapLoginService: @unchecked Sendable {

    public static let shared = OneTapLoginService()

    private var isInitialized = false
    private var authSecret: String?

    // Class-level handlers for the active login page session.
    // Stored here (not in closures) so a new startLoginPage call can overwrite them,
    // automatically invalidating any callbacks still held by the SDK singleton.
    private var onLoginSuccess: ((String) -> Void)?
    private var onLoginSwitch: (() -> Void)?
    private var onLoginCancel: (() -> Void)?

    private init() {}

    /// 同步设置 secret，供 AppContainer 启动时调用。实际初始化延迟到首次使用时。
    public func configure(secret: String) {
        authSecret = secret
    }

    private func ensureInitialized() async -> Bool {
        if isInitialized { return true }
        guard let secret = authSecret else { return false }
        do {
            try await initialize(secret: secret)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Initialize

    public func initialize(secret: String) async throws {
        #if canImport(ATAuthSDK_D)
        self.authSecret = secret
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[String: String], Never>) in
            TXCommonHandler.sharedInstance().setAuthSDKInfo(secret) { resultDic in
                let safe = (resultDic as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
                continuation.resume(returning: safe)
            }
        }

        let code = result["resultCode"] ?? ""
        if code == "600000" {
            isInitialized = true
        } else {
            let msg = result["msg"] ?? "未知错误"
            throw OneTapLoginError.initializeFailed(msg)
        }
        #else
        throw OneTapLoginError.sdkNotAvailable
        #endif
    }

    // MARK: - Check Availability

    public func checkAvailability() async -> Bool {
        #if canImport(ATAuthSDK_D)
        guard await ensureInitialized() else { return false }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
            TXCommonHandler.sharedInstance().checkEnvAvailable(with: .loginToken) { resultDic in
                let safe = (resultDic as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
                continuation.resume(returning: safe)
            }
        }

        guard let result, let code = result["resultCode"] else { return false }
        return code == "600000"
        #else
        return false
        #endif
    }

    // MARK: - Pre-warm

    public func preWarm() async {
        #if canImport(ATAuthSDK_D)
        guard await ensureInitialized() else { return }

        _ = await withCheckedContinuation { (continuation: CheckedContinuation<[String: String], Never>) in
            TXCommonHandler.sharedInstance().accelerateLoginPage(withTimeout: 3.0) { resultDic in
                let safe = (resultDic as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
                continuation.resume(returning: safe)
            }
        }
        #endif
    }

    // MARK: - Start Login Page

    /// 展示阿里一键登录页面并注册事件回调。
    /// SDK 的 getLoginToken 是事件流（页面存活期间持续回调），不适合 async/await，
    /// 所以用回调显式分发各终态事件。
    public func startLoginPage(
        colorScheme: ColorScheme,
        onSuccess: @escaping (String) -> Void,
        onSwitch: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        #if canImport(ATAuthSDK_D)
        guard let presenter = topMostViewController() else { return }

        // Overwriting handlers invalidates the previous session:
        // old SDK callbacks still fire but self.onLoginSuccess/Switch/Cancel are already nil.
        onLoginSuccess = onSuccess
        onLoginSwitch = onSwitch
        onLoginCancel = onCancel

        let model = buildCustomModel(colorScheme: colorScheme)
        TXCommonHandler.sharedInstance().getLoginToken(
            withTimeout: 3.0, controller: presenter, model: model
        ) { [weak self] resultDic in
            guard let self else { return }
            let dict = (resultDic as? [String: Any]) ?? [:]
            let code = dict["resultCode"] as? String ?? ""
            self.handleSDKEvent(code: code, dict: dict)
        }
        #endif
    }

    #if canImport(ATAuthSDK_D)
    private func handleSDKEvent(code: String, dict: [String: Any]) {
        switch code {
        case "600000": // 获取 token 成功
            guard let token = dict["token"] as? String, !token.isEmpty else {
                fireCancel()
                return
            }
            let handler = onLoginSuccess
            clearHandlers()
            handler?(token)

        case "700001": // 用户点击"切换其他登录方式"
            let handler = onLoginSwitch
            clearHandlers()
            handler?()

        case "700000", // 用户主动关闭授权页
             "700010": // 页面被系统挂起/销毁
            fireCancel()

        default:
            // 所有其他事件码（600001 授权页唤起、700002 点击登录按钮、
            // 700003 点击 CheckBox、以及 SDK 隐私弹窗相关的中间事件）均忽略，
            // 继续等待真正的终态（600000 / 700001 / 700000 / 700010）到来。
            // 不能在这里 fireCancel()，否则 privacyAlertIsNeedAutoLogin 流程中
            // SDK 在 700002 → 600000 之间触发的中间事件会提前清空 handlers。
            return
        }
    }

    private func fireCancel() {
        let handler = onLoginCancel
        clearHandlers()
        handler?()
    }

    private func clearHandlers() {
        onLoginSuccess = nil
        onLoginSwitch = nil
        onLoginCancel = nil
    }
    #endif

    // MARK: - Dismiss

    public func dismiss() {
        #if canImport(ATAuthSDK_D)
        TXCommonHandler.sharedInstance().cancelLoginVC(animated: true, complete: nil)
        #endif
    }

    // MARK: - Custom Model

    #if canImport(ATAuthSDK_D)
    private func buildCustomModel(colorScheme: ColorScheme) -> TXCustomModel {
        let model = TXCustomModel()

        // MARK: Orientation & status bar
        model.supportedInterfaceOrientations = .portrait
        model.prefersStatusBarHidden = false
        model.preferredStatusBarStyle = colorScheme == .dark ? .lightContent : .darkContent

        // MARK: Colors
        // SDK stores UIColor values as-is without re-evaluating dynamic colors at render time.
        // Build a UITraitCollection from SwiftUI's ColorScheme (passed from the view's
        // @Environment) and resolve every semantic color against it before handing to the SDK.
        let isDark = colorScheme == .dark
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)

        let brandOrange   = UIColor(red: 1.0, green: 0.42, blue: 0.24, alpha: 1.0)
        let orangePressed = UIColor(red: 0.90, green: 0.35, blue: 0.18, alpha: 1.0)
        let resolvedBg    = UIColor.systemBackground.resolvedColor(with: traits)
        let resolvedLabel = UIColor.label.resolvedColor(with: traits)
        let dynamicSecond = UIColor.secondaryLabel.resolvedColor(with: traits)
        let resolvedThird = UIColor.tertiaryLabel.resolvedColor(with: traits)

        let iconColor = isDark ? UIColor.white : UIColor(white: 0.1, alpha: 1.0)
        let symbolCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        model.backgroundColor = resolvedBg

        // MARK: Nav bar — blends with background, empty title, custom close icon
        model.navIsHidden = false
        model.navColor = resolvedBg
        model.navTitle = NSAttributedString(string: "")
        if let xmark = UIImage(systemName: "xmark", withConfiguration: symbolCfg)?
            .withTintColor(iconColor, renderingMode: .alwaysOriginal) {
            model.navBackImage = xmark
        }
        // Move close button slightly inward so it doesn't hug the edge
        model.navBackButtonFrameBlock = { _, _, frame in
            CGRect(x: 16, y: frame.minY, width: frame.width, height: frame.height)
        }

        // MARK: Logo & SDK slogan — hidden; we add our own labels via customViewBlock
        model.logoIsHidden = true
        model.sloganIsHidden = true

        // MARK: Custom labels: welcome title + registration hint
        // UILabel picks up trait changes automatically, unlike a rendered UIImage
        var welcomeLabel: UILabel?
        var hintLabel: UILabel?

        model.customViewBlock = { superView in
            let welcome = UILabel()
            welcome.text = "欢迎使用 DreamAI"
            welcome.font = .systemFont(ofSize: 24, weight: .bold)
            welcome.textColor = .label
            welcome.textAlignment = .center
            superView.addSubview(welcome)
            welcomeLabel = welcome

            let hint = UILabel()
            hint.text = "首次登录将自动注册账号"
            hint.font = .systemFont(ofSize: 14)
            hint.textColor = .tertiaryLabel
            hint.textAlignment = .center
            superView.addSubview(hint)
            hintLabel = hint
        }

        model.customViewLayoutBlock = { _, contentViewFrame, _, _, _, _, numberFrame, _, _, _ in
            let w = contentViewFrame.width
            // Welcome text sits 56pt above the phone number
            welcomeLabel?.frame = CGRect(x: 0, y: numberFrame.minY - 86, width: w, height: 34)
            // Registration hint sits 8pt below the phone number
            hintLabel?.frame = CGRect(x: 0, y: numberFrame.maxY + 8, width: w, height: 20)
        }

        // MARK: Phone number
        model.numberColor = resolvedLabel
        model.numberFont = UIFont.systemFont(ofSize: 32, weight: .bold)

        // MARK: Login button — full-width minus 24pt margins, 54pt height
        model.loginBtnText = NSAttributedString(
            string: "本机号码一键登录",
            attributes: [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
            ]
        )
        if let activeBg  = makeRoundedResizableImage(brandOrange,   height: 54, cornerRadius: 14),
           let pressedBg = makeRoundedResizableImage(orangePressed.withAlphaComponent(0.68), height: 54, cornerRadius: 14) {
            model.loginBtnBgImgs = [activeBg, pressedBg, pressedBg]   // normal, highlighted, disabled
        }
        model.loginBtnFrameBlock = { screenSize, _, frame in
            CGRect(x: 24, y: frame.minY, width: screenSize.width - 48, height: 54)
        }

        // MARK: Switch button
        model.changeBtnIsHidden = false
        model.changeBtnTitle = NSAttributedString(
            string: "其他手机号登录",
            attributes: [
                .foregroundColor: dynamicSecond,
                .font: UIFont.systemFont(ofSize: 15)
            ]
        )

        // MARK: Checkbox
        model.checkBoxIsHidden = false
        model.checkBoxIsChecked = false
        model.checkBoxWH = 15
        model.checkBoxVerticalCenter = false
        // Load checkbox images from our SPM resource bundle (bypasses SDK's internal bundle lookup)
        if let sdkBundle = Bundle.module.url(forResource: "ATAuthSDK", withExtension: "bundle")
            .flatMap(Bundle.init(url:)),
           let unchecked = UIImage(named: "icon_uncheck", in: sdkBundle, compatibleWith: nil),
           let checked   = UIImage(named: "icon_check",   in: sdkBundle, compatibleWith: nil) {
            model.checkBoxImages = [unchecked, checked]
        }
        // MARK: Privacy — brand orange for links
        model.privacyOne       = ["《DreamAI 用户协议》", AgreementURLs.terms.absoluteString]
        model.privacyTwo       = ["《DreamAI 隐私政策》", AgreementURLs.privacy.absoluteString]
        model.privacyPreText   = "登录即表示你已阅读并同意"
        model.privacySufText   = ""
        model.privacyAlignment = .center
        model.privacyFont      = UIFont.systemFont(ofSize: 12)
        model.privacyColors    = [resolvedThird, brandOrange]
        model.privacyOneColor  = brandOrange
        model.privacyTwoColor  = brandOrange

        // MARK: 二次协议弹窗 — 未勾选时点击登录触发，同意后 SDK 自动执行登录
        //
        // Layout (坐标均相对弹窗自身):
        //  ┌──────────────────────────────────┐  ← alertHeight = 280pt
        //  │  [×]                             │  y=0,  h=44  close button
        //  │    请阅读并同意以下条款            │  y=16, h=28  title
        //  │  ─────────────────────────────   │  y=52  divider(1pt)
        //  │  登录即表示你已阅读并同意          │  y=60, auto-height  content
        //  │  《用户协议》和《隐私政策》         │
        //  │                                  │
        //  │  ┌──────────────────────────┐    │  y=alertH-74, h=50  button
        //  │  │       同意并登录          │    │
        //  │  └──────────────────────────┘    │
        //  │                              24pt│
        //  └──────────────────────────────────┘

        let alertH: CGFloat = 220
        let hPad:   CGFloat = 28   // 左右内边距
        let btnH:   CGFloat = 50
        let btnBottomPad: CGFloat = 24

        model.privacyAlertIsNeedShow       = true
        model.privacyAlertIsNeedAutoLogin  = true
        
        // 弹窗主背景色设计
        // 浅色纯白 (#FFFFFF)；深色使用苹果标准的高级弹窗黑 (#1C1C1E)，比纯黑略浅，增加悬浮立体感
        let alertDarkBg = UIColor(red: 28/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1.0)
        let alertLightBg = UIColor.white
        model.privacyAlertBackgroundColor = colorScheme == .dark ? alertDarkBg : alertLightBg
        model.privacyAlertCornerRadiusArray = [20, 20, 20, 20]

        // 弹窗整体尺寸：宽 = 屏幕宽 - 56，高固定 280，居中
        model.privacyAlertFrameBlock = { screenSize, _, _ in
            let w = screenSize.width - 56
            let x = (screenSize.width - w) / 2
            let y = (screenSize.height - alertH) / 2
            return CGRect(x: x, y: y, width: w, height: alertH)
        }

        // 标题
        model.privacyAlertTitleContent         = "请阅读并同意以下条款"
        model.privacyAlertTitleFont            = .systemFont(ofSize: 16, weight: .semibold)
        model.privacyAlertTitleColor           = resolvedLabel
        model.privacyAlertTitleBackgroundColor = UIColor.clear
        model.privacyAlertTitleAlignment       = .center
        model.privacyAlertTitleFrameBlock = { _, superSize, _ in
            CGRect(x: 0, y: 16, width: superSize.width, height: 28)
        }

        // 协议内容文字（高度由 SDK 根据文字量自适应）
        model.privacyAlertContentFont            = .systemFont(ofSize: 14)
        model.privacyAlertLineSpaceDp            = 6
        model.privacyAlertContentBackgroundColor = .clear
        model.privacyAlertContentColors          = [resolvedThird, brandOrange]
        model.privacyAlertOneColor               = brandOrange
        model.privacyAlertTwoColor               = brandOrange
        model.privacyAlertContentAlignment       = .center
        model.privacyAlertPreText                = "登录即表示你已阅读并同意"
        model.privacyAlertSufText                = ""
        model.privacyAlertPrivacyContentFrameBlock = { _, superSize, _ in
            let contentY: CGFloat = 56          // title(16+28) + gap(12)
            let availH = alertH - contentY - btnH - btnBottomPad - 12
            return CGRect(x: hPad, y: contentY, width: superSize.width - hPad * 2, height: availH)
        }

        // 同意按钮
        model.privacyAlertBtnContent        = "同意并登录"
        model.privacyAlertBtnCornerRadius   = 14
        model.privacyAlertButtonFont        = .systemFont(ofSize: 17, weight: .semibold)
        model.privacyAlertButtonTextColors  = [.white, .white]
        if let btnBg      = makeRoundedResizableImage(brandOrange,   height: btnH, cornerRadius: 14),
           let btnPressed = makeRoundedResizableImage(orangePressed, height: btnH, cornerRadius: 14) {
            model.privacyAlertBtnBackgroundImages = [btnBg, btnPressed]
        }
        model.privacyAlertButtonFrameBlock = { _, superSize, _ in
            let btnW = superSize.width - hPad * 2
            let btnX = hPad
            let btnY = alertH - btnH - btnBottomPad
            return CGRect(x: btnX, y: btnY, width: btnW, height: btnH)
        }

        // 右上角关闭按钮
        model.privacyAlertCloseButtonIsNeedShow = true
        if let alertClose = UIImage(systemName: "xmark", withConfiguration: symbolCfg)?
            .withTintColor(iconColor, renderingMode: .alwaysOriginal) {
            model.privacyAlertCloseButtonImage = alertClose
        }
        model.privacyAlertCloseFrameBlock = { _, superSize, _ in
            CGRect(x: superSize.width - 56, y: 0, width: 44, height: 44)
        }

        // 背景蒙层
        model.privacyAlertMaskIsNeedShow    = true
        model.tapPrivacyAlertMaskCloseAlert = true
        model.privacyAlertMaskColor         = .black
        model.privacyAlertMaskAlpha         = 0.5

        // MARK: 协议详情 WebView — 适配深色/浅色
        model.privacyNavColor      = resolvedBg
        model.privacyNavTitleColor = resolvedLabel
        model.privacyNavTitleFont  = .systemFont(ofSize: 17, weight: .semibold)
        if let backImg = UIImage(systemName: "chevron.left", withConfiguration: symbolCfg)?
            .withTintColor(iconColor, renderingMode: .alwaysOriginal) {
            model.privacyNavBackImage = backImg
        }

        return model
    }

    #endif

    // MARK: - Helper

    #if canImport(ATAuthSDK_D)
    private func topMostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}

#if canImport(ATAuthSDK_D)
/// Creates a resizable rounded-rect image. The image is wide enough to contain both corner arcs
/// (cornerRadius * 2 + 1pt), then capped with stretchable insets so it scales to any width
/// without deforming the corners.
private func makeRoundedResizableImage(_ color: UIColor, height: CGFloat, cornerRadius: CGFloat) -> UIImage? {
    let minWidth = cornerRadius * 2 + 1
    let size = CGSize(width: minWidth, height: height)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
        color.setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius).fill()
    }
    let insets = UIEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
    return image.resizableImage(withCapInsets: insets, resizingMode: .stretch)
}
#endif
