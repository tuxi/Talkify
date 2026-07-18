//
//  AIUsageNoticeDialog.swift
//  DesignKit
//
//  Created by OpenAI Codex on 2026/5/13.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public enum AIUsageNoticeType: String, CaseIterable, Sendable {
    case appFirstLaunch
    case uploadMaterial
    case videoGeneration
    case imageGeneration
    case motionControl
    case goodsVideo
    case promptGeneration
    
    public var storageKey: String {
        switch self {
        case .appFirstLaunch:
            return "ai_usage_notice_agreed_v1"
        case .uploadMaterial:
            return "upload_material_notice_agreed_v1"
        case .motionControl:
            return "motion_control_notice_agreed_v1"
        case .goodsVideo:
            return "goods_video_notice_agreed_v1"
        case .videoGeneration:
            return "video_generation_notice_agreed_v1"
        case .imageGeneration:
            return "image_generation_notice_agreed_v1"
        case .promptGeneration:
            return "prompt_generation_notice_agreed_v1"
        }
    }

    public var defaultTitle: String {
        switch self {
        case .appFirstLaunch:
            return "用户授权"
        case .videoGeneration, .imageGeneration:
            return "AI 创作功能使用须知"
        case .uploadMaterial:
            return "上传素材须知"
        case .motionControl:
            return "动作素材上传须知"
        case .goodsVideo:
            return "商品素材上传须知"
        case .promptGeneration:
            return "分析视频上传须知"
        }
    }

    public var defaultContent: String {
        switch self {
        case .appFirstLaunch:
            return Self.appFirstLaunchContent
        case .uploadMaterial, .videoGeneration, .imageGeneration, .motionControl, .goodsVideo, .promptGeneration:
            return Self.generalContent
        }
    }

    private static let appFirstLaunchContent = """
    欢迎使用 DreamAI（梦境AI）！DreamAI 是一款提供视频、图片生成与 AI 创作能力的创意生产力应用。

    您同意隐私政策仅代表您知悉并同意使用基本功能时，我们处理相关必要个人信息，不代表您同意我们其他扩展功能处理个人信息。其它扩展功能如需收集个人信息，我们将在您使用具体扩展功能时再次征求您的同意。

    如您已阅读并同意，请点击“同意”，开始使用我们的产品及服务；如您不同意，可点击“不同意”，放弃使用我们的产品及服务。欢迎查阅[《用户协议》](dreamai://user-agreement)和[《隐私政策》](dreamai://privacy-policy)了解更多详细信息。
    """

    private static let generalContent = """
    # 欢迎使用 DreamAI（梦境AI）创作功能

    为了完成 AI 图片、视频生成及相关创作任务，DreamAI 需要将您主动输入或上传的数据发送至第三方 AI 服务提供商进行处理。

    可能发送的数据包括：

    - 文字描述与生成提示词
    - 上传的图片、视频、音频等素材
    - 商品信息与生成参数
    - 上传素材中包含的人物或场景内容

    数据可能发送至以下第三方 AI 服务提供商：

    - DeepSeek（文本生成）
    - 阿里云通义（图片生成）
    - 火山引擎（视频生成）
    - 可灵 Kling（视频生成）

    上述数据仅用于完成您当前请求的 AI 生成任务、内容安全审核、生成结果返回及必要的故障排查，不会用于未经授权的模型训练或其他用途。

    DreamAI 不提供人脸识别、身份验证、生物特征识别或 AI 换脸功能，也不会提取、分析或存储任何生物特征信息。

    如果您不同意相关数据处理，您将无法继续使用 AI 上传与生成功能。

    使用前请确认：

    1. 您上传的素材为您本人所有或已获得合法授权；
    2. 请勿上传违法违规、侵权、色情低俗、暴力血腥或涉及未成年人不当内容；
    3. AI 生成结果由系统自动生成，仅供创作参考，您应对上传素材及生成内容承担相应责任。

    点击“同意并继续”即表示您已阅读并同意 DreamAI 将上述数据发送至第三方 AI 服务提供商，用于完成当前 AI 生成任务。

    您可进一步阅读：[《隐私政策》](dreamai://privacy-policy) 和 [《AI 数据处理说明》](dreamai://ai-data-processing)。
    """
}

public enum AIUsageNoticeStorage {
    public static func hasAgreed(_ noticeType: AIUsageNoticeType) -> Bool {
        UserDefaults.standard.bool(forKey: noticeType.storageKey)
    }

    public static func markAgreed(_ noticeType: AIUsageNoticeType) {
        UserDefaults.standard.set(true, forKey: noticeType.storageKey)
    }

    public static func clearAgreement(_ noticeType: AIUsageNoticeType) {
        UserDefaults.standard.removeObject(forKey: noticeType.storageKey)
    }

    public static func clearAllAgreements() {
        AIUsageNoticeType.allCases.forEach { noticeType in
            clearAgreement(noticeType)
        }
    }
}

public struct AIUsageNoticePresenter: @unchecked Sendable {
    private let requestHandler: @MainActor (AIUsageNoticeType, @escaping () -> Void, @escaping () -> Void) -> Void

    public init(
        requestHandler: @escaping @MainActor (AIUsageNoticeType, @escaping () -> Void, @escaping () -> Void) -> Void = { noticeType, onAgree, onCancel in
            if AIUsageNoticeStorage.hasAgreed(noticeType) {
                onAgree()
            } else {
                AIUsageNoticeOverlayCenter.shared.request(
                    noticeType,
                    onAgree: onAgree,
                    onCancel: onCancel
                )
            }
        }
    ) {
        self.requestHandler = requestHandler
    }

    @MainActor
    public func request(
        _ noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        requestHandler(noticeType, onAgree, onCancel)
    }
}

@MainActor
public final class AIUsageNoticeOverlayCenter: ObservableObject {
    public static let shared = AIUsageNoticeOverlayCenter()

    @Published fileprivate var activeNotice: ActiveNotice?

    #if os(iOS)
    private var overlayWindow: UIWindow?
    #elseif os(macOS)
    private var overlayWindow: NSWindow?
    #endif
    private var openURLHandler: (@MainActor (URL) -> Void)?

    private init() {}

    public func setOpenURLHandler(_ handler: @escaping @MainActor (URL) -> Void) {
        openURLHandler = handler
    }

    public func request(
        _ noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        if AIUsageNoticeStorage.hasAgreed(noticeType) {
            onAgree()
            return
        }

        activeNotice = ActiveNotice(
            noticeType: noticeType,
            onAgree: onAgree,
            onCancel: onCancel
        )
        showOverlayIfNeeded()
    }

    fileprivate func agree() {
        let completion = activeNotice?.onAgree
        dismissOverlay()
        completion?()
    }

    fileprivate func cancel() {
        let completion = activeNotice?.onCancel
        dismissOverlay()
        completion?()
    }

    private func showOverlayIfNeeded() {
        #if os(iOS)
        guard overlayWindow == nil,
              let windowScene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else {
            overlayWindow?.isHidden = false
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 100
        window.backgroundColor = .clear
        let controller = UIHostingController(rootView: AIUsageNoticeOverlayHost(center: self))
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = false
        overlayWindow = window
        #elseif os(macOS)
        guard overlayWindow == nil else {
            overlayWindow?.orderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .modalPanel
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: AIUsageNoticeOverlayHost(center: self))
        window.center()
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
        #endif
    }

    private func dismissOverlay() {
        activeNotice = nil
        #if os(iOS)
        overlayWindow?.isHidden = true
        overlayWindow = nil
        #elseif os(macOS)
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        #endif
    }

    fileprivate func openURL(_ url: URL) -> OpenURLAction.Result {
        guard let openURLHandler else {
            return .systemAction
        }
        openURLHandler(url)
        return .handled
    }
}

fileprivate struct ActiveNotice {
    let noticeType: AIUsageNoticeType
    let onAgree: () -> Void
    let onCancel: () -> Void
}

private struct AIUsageNoticeOverlayHost: View {
    @ObservedObject var center: AIUsageNoticeOverlayCenter

    var body: some View {
        ZStack {
            if let notice = center.activeNotice {
                AIUsageNoticePresentation(
                    title: notice.noticeType.defaultTitle,
                    content: notice.noticeType.defaultContent,
                    noticeType: notice.noticeType,
                    onAgree: {
                        center.agree()
                    },
                    onCancel: {
                        center.cancel()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.openURL, OpenURLAction { url in
            center.openURL(url)
        })
    }
}

private struct AIUsageNoticePresenterKey: EnvironmentKey {
    static let defaultValue = AIUsageNoticePresenter()
}

public extension EnvironmentValues {
    var aiUsageNoticePresenter: AIUsageNoticePresenter {
        get { self[AIUsageNoticePresenterKey.self] }
        set { self[AIUsageNoticePresenterKey.self] = newValue }
    }
}

private struct AIUsageNoticePresentation: View {
    let title: String
    let content: AttributedString
    let primaryButtonTitle: String
    let secondaryButtonTitle: String
    let noticeType: AIUsageNoticeType
    let onAgree: () -> Void
    let onCancel: () -> Void

    init(
        title: String,
        content: String,
        primaryButtonTitle: String = "同意并继续",
        secondaryButtonTitle: String = "我再想想",
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            title: title,
            content: Self.makeMarkdownContent(content),
            primaryButtonTitle: primaryButtonTitle,
            secondaryButtonTitle: secondaryButtonTitle,
            noticeType: noticeType,
            onAgree: onAgree,
            onCancel: onCancel
        )
    }

    private static func makeMarkdownContent(_ content: String) -> AttributedString {
        let attributed = (
            try? AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        ) ?? AttributedString(content)

        return styledMarkdownContent(attributed)
    }

    private static func styledMarkdownContent(_ content: AttributedString) -> AttributedString {
        var styled = content
        styled.font = .system(size: 14, weight: .regular)
        styled.foregroundColor = .secondary

        for run in styled.runs {
            if run.presentationIntent?.components.contains(where: { component in
                if case .header = component.kind { return true }
                return false
            }) == true {
                styled[run.range].font = .system(size: 17, weight: .bold)
            }

            if run.link != nil {
                styled[run.range].foregroundColor = .accentColor
                styled[run.range].underlineStyle = .single
            }
        }

        return styled
    }

    init(
        title: String,
        content: AttributedString,
        primaryButtonTitle: String = "同意并继续",
        secondaryButtonTitle: String = "我再想想",
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.content = content
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.noticeType = noticeType
        self.onAgree = onAgree
        self.onCancel = onCancel
    }

    var body: some View {
        if noticeType == .appFirstLaunch {
            AIAppAuthorizationNoticeSheet(
                title: title,
                content: content,
                primaryButtonTitle: primaryButtonTitle == "同意并继续" ? "同意" : primaryButtonTitle,
                secondaryButtonTitle: secondaryButtonTitle == "我再想想" ? "不同意" : secondaryButtonTitle,
                noticeType: noticeType,
                onAgree: onAgree,
                onCancel: onCancel
            )
        } else {
            AIUsageNoticeDialog(
                title: title,
                content: content,
                primaryButtonTitle: primaryButtonTitle,
                secondaryButtonTitle: secondaryButtonTitle,
                noticeType: noticeType,
                onAgree: onAgree,
                onCancel: onCancel
            )
        }
    }
}

private struct AIAppAuthorizationNoticeSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: AttributedString
    let primaryButtonTitle: String
    let secondaryButtonTitle: String
    let noticeType: AIUsageNoticeType
    let onAgree: () -> Void
    let onCancel: () -> Void
    @State private var measuredContentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let panelMaxHeight = min(proxy.size.height * 0.58, 540)
            let bottomInset = max(proxy.safeAreaInsets.bottom, 10)
            let contentMaxHeight = max(140, panelMaxHeight - 154 - bottomInset)
            let contentHeight = min(
                measuredContentHeight > 0 ? measuredContentHeight : 1,
                contentMaxHeight
            )
            let needsScroll = measuredContentHeight > contentMaxHeight + 1

            ZStack(alignment: .bottom) {
                Color.black.opacity(colorScheme == .dark ? 0.46 : 0.38)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(sheetPrimaryTextColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                        .padding(.bottom, 16)

                    ScrollView(showsIndicators: needsScroll) {
                        Text(content)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(sheetSecondaryTextColor)
                            .lineSpacing(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .tint(primaryTint)
                            .readAIUsageNoticeHeight { height in
                                measuredContentHeight = height
                            }
                    }
                    .scrollDisabled(!needsScroll)
                    .frame(height: contentHeight)
                    .padding(.horizontal, 28)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: needsScroll ? .clear : .black, location: 0),
                                .init(color: .black, location: needsScroll ? 0.04 : 0),
                                .init(color: .black, location: needsScroll ? 0.92 : 1),
                                .init(color: needsScroll ? .clear : .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    HStack(spacing: 12) {
                        Button(action: onCancel) {
                            Text(secondaryButtonTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(secondaryButtonTextColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(disagreeButtonColor)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            AIUsageNoticeStorage.markAgreed(noticeType)
                            onAgree()
                        } label: {
                            Text(primaryButtonTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(primaryTint)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .shadow(color: primaryTint.opacity(0.22), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, bottomInset + 10)
                }
                .frame(maxWidth: .infinity)
                .background(sheetSurfaceColor)
                .clipShape(AITopRoundedRectangle(radius: 28))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.20), radius: 24, x: 0, y: -10)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var primaryTint: Color {
        Color(red: 0.95, green: 0.25, blue: 0.36)
    }

    private var sheetSurfaceColor: Color {
        #if os(macOS)
        Color(nsColor: colorScheme == .dark ? .windowBackgroundColor : .textBackgroundColor)
        #else
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.13)
            : Color(uiColor: .systemBackground)
        #endif
    }

    private var disagreeButtonColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.13)
            : Color.black.opacity(0.055)
    }

    private var sheetPrimaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88)
    }

    private var sheetSecondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.86) : .black.opacity(0.72)
    }

    private var secondaryButtonTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.82)
    }
}

private struct AITopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

public struct AIUsageNoticeDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    private let title: String
    private let content: AttributedString
    private let primaryButtonTitle: String
    private let secondaryButtonTitle: String
    private let noticeType: AIUsageNoticeType
    private let onAgree: () -> Void
    private let onCancel: () -> Void
    @State private var measuredContentHeight: CGFloat = 0

    public init(
        title: String,
        content: String,
        primaryButtonTitle: String = "同意并继续",
        secondaryButtonTitle: String = "我再想想",
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            title: title,
            content: (try? AttributedString(markdown: content)) ?? AttributedString(content),
            primaryButtonTitle: primaryButtonTitle,
            secondaryButtonTitle: secondaryButtonTitle,
            noticeType: noticeType,
            onAgree: onAgree,
            onCancel: onCancel
        )
    }

    public init(
        title: String,
        content: AttributedString,
        primaryButtonTitle: String = "同意并继续",
        secondaryButtonTitle: String = "我再想想",
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.content = content
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.noticeType = noticeType
        self.onAgree = onAgree
        self.onCancel = onCancel
    }

    public var body: some View {
        GeometryReader { proxy in
            let dialogWidth = min(proxy.size.width - 48, 500)
            let dialogMaxHeight = min(proxy.size.height * 0.74, 590)
            let contentMaxHeight = max(150, dialogMaxHeight - 220)
            let contentViewportHeight = min(
                measuredContentHeight > 0 ? measuredContentHeight : 1,
                contentMaxHeight
            )
            let needsScroll = measuredContentHeight > contentMaxHeight + 1

            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.62 : 0.50)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(primaryTextColor)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        ScrollView(showsIndicators: true) {
                            Text(content)
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .tint(primaryTint)
                                .readAIUsageNoticeHeight { height in
                                    measuredContentHeight = height
                                }
                        }
                        .scrollDisabled(!needsScroll)
                        .frame(height: contentViewportHeight)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(contentBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        }
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: needsScroll ? .clear : .black, location: 0),
                                    .init(color: .black, location: needsScroll ? 0.04 : 0),
                                    .init(color: .black, location: needsScroll ? 0.9 : 1),
                                    .init(color: needsScroll ? .clear : .black, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .padding(.top, 22)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    VStack(spacing: 10) {
                        Rectangle()
                            .fill(borderColor)
                            .frame(height: 1)
                            .padding(.horizontal, -24)

                        Button {
                            AIUsageNoticeStorage.markAgreed(noticeType)
                            onAgree()
                        } label: {
                            Text(primaryButtonTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(primaryTint)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .shadow(color: primaryTint.opacity(0.22), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 0)

                        Button(action: onCancel) {
                            Text(secondaryButtonTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(secondaryButtonTextColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 0)
                    .padding(.bottom, 18)
                    .background(surfaceColor)
                }
                .frame(width: dialogWidth)
                .frame(maxHeight: dialogMaxHeight)
                .background(surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.40 : 0.18), radius: 26, x: 0, y: 14)
                .padding(.horizontal, 24)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var primaryTint: Color {
        Color(red: 0.95, green: 0.25, blue: 0.36)
    }

    private var surfaceColor: Color {
        #if os(macOS)
        Color(nsColor: colorScheme == .dark ? .windowBackgroundColor : .textBackgroundColor)
        #else
        Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
        #endif
    }

    private var contentBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.42 : 0.55)
        #else
        Color(uiColor: colorScheme == .dark ? .tertiarySystemBackground : .secondarySystemBackground)
        #endif
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.64)
    }

    private var secondaryButtonTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.82)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.055)
    }
}

public struct AIUploadComplianceHint: View {
    private let text: String

    public init(_ text: String = "请确保上传内容合规且已获得合法授权。") {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

public extension View {
    func aiUsageNoticeDialog(
        isPresented: Binding<Bool>,
        title: String,
        content: String,
        primaryButtonTitle: String = "同意并继续",
        secondaryButtonTitle: String = "我再想想",
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                AIUsageNoticePresentation(
                    title: title,
                    content: content,
                    primaryButtonTitle: primaryButtonTitle,
                    secondaryButtonTitle: secondaryButtonTitle,
                    noticeType: noticeType,
                    onAgree: onAgree,
                    onCancel: onCancel
                )
                .environment(\.openURL, OpenURLAction { url in
                    AIUsageNoticeOverlayCenter.shared.openURL(url)
                })
                .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresented.wrappedValue)
    }

    func aiUsageNoticeDialog(
        isPresented: Binding<Bool>,
        title: String,
        content: AttributedString,
        primaryButtonTitle: String = "同意并继续",
        secondaryButtonTitle: String = "我再想想",
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                AIUsageNoticePresentation(
                    title: title,
                    content: content,
                    primaryButtonTitle: primaryButtonTitle,
                    secondaryButtonTitle: secondaryButtonTitle,
                    noticeType: noticeType,
                    onAgree: onAgree,
                    onCancel: onCancel
                )
                .environment(\.openURL, OpenURLAction { url in
                    AIUsageNoticeOverlayCenter.shared.openURL(url)
                })
                .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresented.wrappedValue)
    }

    func aiUsageNoticeDialog(
        isPresented: Binding<Bool>,
        noticeType: AIUsageNoticeType,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        aiUsageNoticeDialog(
            isPresented: isPresented,
            title: noticeType.defaultTitle,
            content: noticeType.defaultContent,
            noticeType: noticeType,
            onAgree: onAgree,
            onCancel: onCancel
        )
    }
}

private struct AIUsageNoticeHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readAIUsageNoticeHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: AIUsageNoticeHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(AIUsageNoticeHeightPreferenceKey.self, perform: onChange)
    }
}
