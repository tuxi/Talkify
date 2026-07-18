//
//  WebSocketClient.swift
//  SignalX
//
//  Created by xiaoyuan on 2025/10/20.
//

import Network
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 状态定义
public enum ConnectionState: Equatable {
    // 包含导致断开的错误。如果是用户主动断开，Error? 为 nil 或 .userDisconnected
    case disconnected(Error?)
    // 正在尝试建立连接。attempt 为当前尝试的次数 (1, 2, 3...)
    case connecting(attempt: Int)
    case connected
    case disconnecting
    
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
            // 忽略 Error 的具体实例，只要都是 disconnected 就认为是相等状态
        case (.disconnected, .disconnected): return true
        case (.connecting(let lAttempt), .connecting(let rAttempt)): return lAttempt == rAttempt
        case (.connected, .connected): return true
        case (.disconnecting, .disconnecting): return true
        default: return false
        }
    }
}

/**
 错误枚举：用于更清晰地传递断开连接或发送失败的原因。
 */
enum WebSocketClientError: Error, Equatable {
    // sendFailed 的关联值从 Error 改为 String (存储 Error 的描述，用于比较)
    case sendFailed(String)
    case maxReconnectAttemptsReached
    case userDisconnected
    case preflightFailed
    case unknown
    case unauthorized
    
    // MARK: - Equatable (必须实现)
    static func == (lhs: WebSocketClientError, rhs: WebSocketClientError) -> Bool {
        switch (lhs, rhs) {
        case (.sendFailed(let lDescription), .sendFailed(let rDescription)):
            // 对于 sendFailed，比较它们的描述是否相同
            return lDescription == rDescription
        case (.maxReconnectAttemptsReached, .maxReconnectAttemptsReached),
            (.userDisconnected, .userDisconnected),
            (.preflightFailed, .preflightFailed),
            (.unknown, .unknown),
            (.unauthorized, .unauthorized):
            // 对于不带关联值的 case，直接比较类型
            return true
        default:
            return false
        }
    }
    
    // MARK: - Localized Description (保持不变)
    var localizedDescription: String {
        switch self {
        case .sendFailed(let description): return "消息发送失败: \(description)"
        case .maxReconnectAttemptsReached: return "达到最大重连次数限制。"
        case .userDisconnected: return "用户或应用主动断开连接。"
        case .preflightFailed: return "连接前置校验失败。"
        case .unknown: return "发生未知连接错误。"
        case .unauthorized: return "服务端返回 401 Unauthorized"
        }
    }
    
    // MARK: - 辅助创建方法（方便从原始 Error 创建）
    static func from(underlyingError error: Error) -> WebSocketClientError {
        return .sendFailed(error.localizedDescription)
    }
}

public class WebSocketClient: NSObject, @unchecked Sendable {
    private enum ReconnectTrigger: String {
        case socketDisconnect = "socket_disconnect"
        case preflightFailure = "preflight_failure"
    }
    
    // MARK: - 私有核心组件
    private var webSocketTask: URLSessionWebSocketTask?
//    private var urlRequest: URLRequest?
    private var session: URLSession!
    
    // 状态管理
    public private(set) var state: ConnectionState = .disconnected(nil)
    // 连接意图: 决定意外断开时是否应自动重连。
    // true: 意外断开时重连 (默认)
    // false: 主动断开，不重连
    private var shouldReconnect = true
    private let maxReconnectAttempts = 10
    
    // MARK: - 心跳机制
    private var pingTimer: DispatchSourceTimer?
    private let pingInterval: TimeInterval = 15.0 // 每隔 15 秒发送心跳
#if os(iOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif
    private var backgroundDisconnectTimer: Timer?
    private let backgroundDisconnectDelay: TimeInterval = 10.0
    
    // MARK: - 消息队列 (线程安全：由 trySendNext 的串行逻辑保证)
    private var sendQueue = [String]()
    private var isSending = false
    
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "socket.client.network.monitor")
    private var hasInitialNetworkStatus = false
    
    // MARK: - 回调 (统一在主线程调用)
    public var onReceive: (@Sendable (Data) -> Void)?
    public var onConnected: (@Sendable () -> Void)?
    public var onDisconnected: (@Sendable (Error?) -> Void)?
    public var onUnauthorized: (@Sendable () -> Void)?
    public var connectionValidatorRequest: (@Sendable () async -> URLRequest?)?
    
    private let identifier: String
    
    private var isAppActive: Bool {
#if os(iOS)
        return UIApplication.shared.applicationState == .active
#else
        // macOS 上只要 App 没退出且电脑没休眠，就视为 Active
        return true
#endif
    }
    
    // MARK: - 初始化
    
    public init(identifier: String? = nil) {
        if let identifier, !identifier.isEmpty {
            self.identifier = identifier
        } else {
            self.identifier = "dreamlog.default"
        }
        super.init()
        
        let configuration = URLSessionConfiguration.default
        // 将 delegateQueue 设为 nil，让 URLSession 使用一个串行后台队列
        // 手动在 delegate 方法中将状态和回调转回主线程。
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        setupNotifications()
    }
    
    
    deinit {
        // 清理通知监听器
        NotificationCenter.default.removeObserver(self)
        // 确保资源被释放
        performDisconnection(reason: WebSocketClientError.userDisconnected)
    }
    
    // MARK: - 连接与断开
    
    /**
     开始连接 WebSocket。
     */
    public func connect() {
        switch self.state {
        case .connected, .connecting(_):
            // 已经连接或正在连接，忽略请求
            DLLog("WebSocketClient.connect() identifier=\(identifier) 已经连接或正在连接，忽略请求")
            return
        case .disconnected(_), .disconnecting:
            // 允许从断开或断开中状态启动连接
            // 明确设置意图：只要调用了 connect，就意味着希望连接保持
            self.shouldReconnect = true
            // 启动连接，尝试次数从 1 开始
            self.startConnecting(attempt: 1)
            DLLog("WebSocketClient.connect() identifier=\(identifier) 从断开或断开中状态启动连接")
        }
    }
    
    private func startConnecting(attempt: Int) {
        if case .connecting = self.state {
            // 如果在异步 Task 切换到 MainActor 期间，状态已被另一个调用改变，则退出
            DLLog("WebSocketClient.startConnecting() identifier=\(identifier) 正在连接中，拒绝本次连接")
            return
        }
        self.state = .connecting(attempt: attempt)
        
        Task {
            guard let validator = connectionValidatorRequest else {
                await MainActor.run {
                    self.handlePreflightFailure(attempt: attempt, reason: .preflightFailed)
                }
                return
            }
            guard let request = await validator() else {
                await MainActor.run {
                    self.handlePreflightFailure(attempt: attempt, reason: .preflightFailed)
                }
                return
            }
            
            await MainActor.run {
                
                self.webSocketTask?.cancel()
                self.webSocketTask = session.webSocketTask(with: request)
                self.webSocketTask?.resume()
                self.listen()
                // 仅在 connect 时启动网络监听
                startNetworkMonitor()
                DLLog("WebSocketClient.startConnecting() identifier=\(identifier) 开始连接Websocket... (尝试次数: \(attempt))")
            }
        }
    }
    
    @MainActor
    private func handlePreflightFailure(attempt: Int, reason: WebSocketClientError) {
        guard case .connecting(let currentAttempt) = self.state, currentAttempt == attempt else {
            return
        }
        
        self.state = .disconnected(reason)
        let willRetry = self.shouldReconnect && self.isAppActive
        DLLog("WebSocketClient.startConnecting() identifier=\(identifier) 前置校验失败，attempt=\(attempt)，shouldReconnect=\(self.shouldReconnect)，isAppActive=\(self.isAppActive)，willRetry=\(willRetry)。")
        
        guard willRetry else {
            DLLog("WebSocketClient.startConnecting() identifier=\(identifier) 前置校验失败后不再重试，停止网络监控。")
            self.stopNetworkMonitor()
            return
        }
        
        DLLog("WebSocketClient.startConnecting() identifier=\(identifier) 前置校验失败后准备进入第 \(attempt) 次重连退避。")
        self.reconnectHandler(nextAttempt: attempt, trigger: .preflightFailure)
    }
    
    // 用户主动断开
    public func disconnect() {
        self.sendQueue.removeAll()
        self.isSending = false
        // 状态更新：明确标记为用户主动断开，并进入 disconnecting 状态
        self.shouldReconnect = false
        // 状态更新：进入 disconnecting
        if case .connected = self.state {
            self.state = .disconnecting
        }
        // 标记为用户主动断开连接
        self.performDisconnection(reason: WebSocketClientError.userDisconnected)
    }
    
    private func performDisconnection(reason: Error?) {
        let oldState = self.state
        // 是否准备断开连接的条件：只要不是已断开状态
        
        // 如果是因为 401 导致的断开，强制停止重连
        if let wsError = reason as? WebSocketClientError,
           case .unauthorized = wsError {
            self.shouldReconnect = false
            self.stopNetworkMonitor()
        }
        
        let alreadyDisconnected = {
            if case .disconnected = oldState {
                return true
            }
            return false
        }()
        
        // 清理资源（无论如何都执行一次，以确保释放）
        self.pingTimer?.cancel()
        self.pingTimer = nil
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        
        // 状态转换：只有非 disconnected 状态时才触发回调与状态更新
        if !alreadyDisconnected {
            self.state = .disconnected(reason)
            // 回调只触发一次
            if case .connected = oldState {
                self.onDisconnected?(reason)
                DLLog("WebSocket Disconnected. identifier=\(identifier) Reason: \(reason?.localizedDescription ?? "Normal close")")
            }
        }
        
        // 确定是否为意外断开 (非用户主动关闭)
        let isUnexpected = (reason as? WebSocketClientError) != .userDisconnected
        
        if self.shouldReconnect && isUnexpected && isAppActive {
            let nextAttempt: Int
            
            if case .connecting(let attempt) = oldState {
                nextAttempt = attempt + 1
            } else if case .connected = oldState {
                // 从 Connected 状态断开，重连次数从 1 开始
                nextAttempt = 1
            } else {
                return // 旧状态不是 Connected 或 Connecting，不应重连
            }
            
            self.reconnectHandler(nextAttempt: nextAttempt, trigger: .socketDisconnect)
        } else {
            stopNetworkMonitor()
        }
    }
    
    // MARK: - 自动重连 (基于状态)
    
    private func reconnectHandler(nextAttempt: Int, trigger: ReconnectTrigger) {
        // 必须在 disconnected 状态才能开始重连
        guard case .disconnected(_) = self.state else { return }
        guard shouldReconnect, isAppActive else { return }
        
        // 检查重连次数 (使用 nextAttempt)
        guard nextAttempt <= maxReconnectAttempts else {
            self.state = .disconnected(WebSocketClientError.maxReconnectAttemptsReached)
            self.shouldReconnect = false
            self.onDisconnected?(WebSocketClientError.maxReconnectAttemptsReached)
            DLLog("WebSocketClient.reconnectHandler() identifier=\(identifier) trigger=\(trigger.rawValue) 重连达到最大次数，停止重连。")
            return
        }
        
        // 指数退避算法: nextAttempt 从 1 开始，所以 pow(2.0, Double(1)) 是 2
        let delay = min(64.0, pow(2.0, Double(nextAttempt)))
        DLLog("WebSocketClient.reconnectHandler() identifier=\(identifier) trigger=\(trigger.rawValue) 尝试重连... (第 \(nextAttempt) 次, 延迟 \(Int(delay)) 秒)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            // 再次检查状态，防止在延迟期间被外部调用 connect/disconnect
            if case .disconnected(_) = self.state, self.shouldReconnect {
                DLLog("WebSocketClient.reconnectHandler() identifier=\(self.identifier) trigger=\(trigger.rawValue) 开始执行第 \(nextAttempt) 次重连。")
                self.startConnecting(attempt: nextAttempt)
            }
        }
    }
    
    // MARK: - 后台/前台处理
    
    private func setupNotifications() {
#if os(iOS)
        // iOS 监听 App 前后台
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
#elseif os(macOS)
        // macOS 监听电脑休眠与唤醒 (这是 macOS 上的“后台”等价逻辑)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppBackground), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppForeground), name: NSWorkspace.didWakeNotification, object: nil)
        
        // 也可以监听 App 隐藏/显示（可选，macOS App 隐藏时通常不建议断开）
        // NotificationCenter.default.addObserver(self, selector: #selector(handleAppBackground), name: NSApplication.didHideNotification, object: nil)
#endif
    }
    
    
    
    // MARK: - 心跳
    private func startPing() {
        pingTimer?.cancel()
        
        // 使用 DispatchQueue.main 保证对 webSocketTask 的操作和状态修改在同一线程上下文 (主线程)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        
        pingTimer = timer
    }
    
    private var pingFailureCount = 0
    // ping 3次失败后才认为失败
    private func sendPing() {
        guard case .connected = self.state else { return }
        webSocketTask?.sendPing { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if error != nil {
                    DLLog("WebSocketClient: identifier=\(self.identifier) Ping failed - \(error!.localizedDescription)")
                    self.pingFailureCount += 1
                    if self.pingFailureCount >= 3 {
                        self.performDisconnection(reason: nil)
                    }
                } else {
                    self.pingFailureCount = 0
                }
            }
        }
    }
    
    // MARK: - 接收消息 (递归监听)
    
    private func listen() {
        // 防御性检查：任务必须存在且当前是已连接状态
        guard let task = webSocketTask else {
            DLLog("WebSocketClient: identifier=\(identifier) ❌ 无法监听，webSocketTask 为 nil。")
            return
        }
        
        // 递归监听必须在 webSocketTask?.resume() 之后立即调用
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            // 确保所有状态更新和回调都在主线程
            DispatchQueue.main.async {
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.onReceive?(text.data(using: .utf8) ?? Data())
                    case .data(let data):
                        // 切换到 Protobuf 后，WebSocket 数据传输方式将从 JSON 字符串 变为 二进制数据 (Data)。因为 Protobuf 的设计就是为了将所有消息封装在一个顶层消息（即 WebSocketMessage）中，并通过 oneof 字段实现类型安全的分发。
                        self.onReceive?(data)
                    @unknown default:
                        DLLog("WebSocketClient: identifier=\(self.identifier) ⚠️ 收到未知类型的 WebSocket 消息")
                    }
                    
                    // 成功接收后，继续监听下一条消息
                    // ✅ 只有在已经连接状态下才继续监听
                    if case .connected = self.state {
                        // 在某些极端情况下（比如服务端频繁关闭连接），给递归加一点延迟以避免 CPU 过高
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.listen()
                        }
                    }
                    
                case .failure(let error):
                    // 常见错误类型检查
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain,
                       nsError.code == NSURLErrorCancelled {
                        DLLog("WebSocketClient: identifier=\(self.identifier) ⚠️ WebSocket 被取消，不触发重连。")
                        self.performDisconnection(reason: WebSocketClientError.userDisconnected)
                        return
                    }
                    DLLog("WebSocketClient: identifier=\(self.identifier) Receive failed - \(error.localizedDescription)")
                    // 接收失败，触发断开/重连逻辑
                    self.performDisconnection(reason: WebSocketClientError.sendFailed(error.localizedDescription))
                }
            }
        }
    }
    
    // MARK: - 发送消息
    
    /**
     发送消息到服务器，使用队列保证发送顺序。
     */
    public func send(_ text: String) {
        // 确保队列操作和发送启动在主线程安全进行
        Task { @MainActor in
            self.sendQueue.append(text)
            self.trySendNext()
        }
    }
    
    private func trySendNext() {
        if isSending {
            return
        }
        guard case .connected = self.state else {
            return
        }
        if sendQueue.isEmpty {
            return
        }
        
        isSending = true
        let message = sendQueue.removeFirst()
        
        webSocketTask?.send(.string(message)) { [weak self] error in
            guard let self = self else { return }
            
            // URLSessionTask 的回调发生在 Delegate Queue (后台)，需切回主线程
            DispatchQueue.main.async {
                self.isSending = false
                
                if let error = error {
                    DLLog("WebSocketClient: identifier=\(self.identifier) Send failed - \(error.localizedDescription)")
                    
                    // 发送失败：将消息回队头部，并尝试触发重连
                    // 去重机制
                    if !self.sendQueue.contains(message) {
                        self.sendQueue.insert(message, at: 0)
                    }
                    self.performDisconnection(reason: WebSocketClientError.sendFailed(error.localizedDescription))
                } else {
                    // 发送成功：尝试发送下一条
                    self.trySendNext()
                }
            }
        }
    }
}

extension WebSocketClient {
    // 启动网络监控（仅在 connect() 时调用）
    private func startNetworkMonitor() {
        // 避免重复创建
        if networkMonitor != nil { return }
        
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            if path.status == .satisfied {// 当用户授权网络访问或网络恢复后
                DispatchQueue.main.async {
                    if case .disconnected = self.state, self.shouldReconnect {
                        DLLog("WebSocketClient：identifier=\(self.identifier) 网络恢复，自动尝试重新连接 WebSocket...")
                        self.connect()
                    }
                }
            } else {
                DLLog("WebSocketClient：identifier=\(identifier) 网络不可用，等待恢复...")
            }
        }
        
        monitor.start(queue: networkQueue)
        networkMonitor = monitor
        DLLog("WebSocketClient：identifier=\(identifier) 网络监控已启动。")
    }
    
    // 停止网络监控（在 disconnect / 销毁时调用）
    private func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
        DLLog("WebSocketClient：identifier=\(identifier) 网络监控已停止。")
    }
    
    @objc private func handleAppBackground() {
        pingTimer?.cancel()
        pingTimer = nil
        
#if os(iOS)
        // --- iOS 专属：后台任务申请 ---
        // 只有在 Connected 状态才启动延迟断开逻辑
        guard case .connected = state else {
            DLLog("SocketClient: identifier=\(identifier) 应用进入后台，连接已断开，无需处理后台延迟断开。")
            return
        }
        
        // 3. 立即请求后台执行时间 (最长约 3 分钟)
        self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "WebSocketDisconnectDelay") {
            // 4. 【系统到期回调】：如果系统时间到期（约 3 分钟），强制执行断开并结束任务
            DLLog("SocketClient: identifier=\(self.identifier) 后台任务时间到期，强制断开 WebSocket。")
            self.backgroundDisconnectTimer?.invalidate()
            self.backgroundDisconnectTimer = nil
            
            Task { @MainActor in
                // 后台超时断开不等于用户主动关闭连接。
                // 保留重连意图，前台恢复后由 handleAppForeground() 负责重新连接。
                self.performDisconnection(reason: WebSocketClientError.userDisconnected) // 强制断开
                self.endBackgroundTask() // 结束任务
            }
        }
        
        
        // 启动 iOS 延迟断开计时器
        self.startBackgroundTimer()
#elseif os(macOS)
        // --- macOS 专属：休眠前立即断开 ---
        // 电脑要睡觉了，主动断开防止 Socket 变成僵尸连接
        DLLog("macOS 将进入休眠，断开连接")
        self.performDisconnection(reason: WebSocketClientError.userDisconnected)
#endif
    }
    
    @objc private func handleAppForeground() {
        // 立即取消后台延迟断开计时器，防止它在连接恢复后触发断开
        backgroundDisconnectTimer?.invalidate()
        backgroundDisconnectTimer = nil
        DLLog("WebSocketClient: identifier=\(identifier) 应用回到前台，取消延迟断开计时器。")
        
        // 结束任何正在运行的后台任务
        self.endBackgroundTask() // 释放后台执行时间
        
        // 2. 检查是否需要重新连接
        // 只有当应重连 (shouldReconnect=true) 且当前处于断开状态时，才尝试恢复连接。
        // shouldReconnect 在 connect() 中被设为 true。
        if self.shouldReconnect, case .disconnected(_) = self.state {
            DLLog("WebSocketClient: identifier=\(identifier) 应用回到前台，尝试恢复连接...")
            // 重新设置 shouldReconnect 为 true (如果它之前被 background 逻辑设为 false)
            self.shouldReconnect = true
            self.connect()
        }
    }
    
    func startBackgroundTimer() {
       
        // 启动 10 秒延迟断开计时器（现在它在一个被延长的后台任务内）
        Task { @MainActor in
            self.backgroundDisconnectTimer?.invalidate()
            
            DLLog("SocketClient: identifier=\(identifier) 应用进入后台，启动 \(backgroundDisconnectDelay) 秒延迟断开计时器，并持有后台任务。")
            
            let timer = Timer(timeInterval: self.backgroundDisconnectDelay,
                              repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    // 6. 【计时器到期】：在 10 秒内执行断开，并主动结束任务
                    if case .connected = self.state {
                        DLLog("SocketClient: identifier=\(self.identifier) 后台计时器到期，执行延迟断开。")
                        self.performDisconnection(reason: WebSocketClientError.userDisconnected)
                    }
                    self.backgroundDisconnectTimer = nil
                    self.endBackgroundTask() // 计时器触发后，立即结束任务
                }
            }
            
            RunLoop.main.add(timer, forMode: .common)
            self.backgroundDisconnectTimer = timer
        }
    }
    
    // MARK: - 后台任务管理
    private func endBackgroundTask() {
#if os(iOS)
        if self.backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
            self.backgroundTaskIdentifier = .invalid
        }
#endif
    }
}

// MARK: - URLSessionTaskDelegate

extension WebSocketClient: URLSessionTaskDelegate {
    // 实现 URLSessionTaskDelegate 以捕获握手响应
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 握手阶段的错误或完成会走到这里
        if let response = task.response as? HTTPURLResponse, response.statusCode == 401 {
                DLLog("WebSocketClient: 握手被拒绝 (401) - Token 彻底失效")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // 1. 停止重连意图，防止无限重试 401 的请求
                    self.shouldReconnect = false
                    self.stopNetworkMonitor()
                    
                    // 2. 触发回调（UI 层会收到这个通知去 logout）
                    self.onUnauthorized?()
                    
                    // 3. 执行物理断开
                    self.performDisconnection(reason: WebSocketClientError.unauthorized)
                }
                return
            }
    }
}


// MARK: - URLSessionWebSocketDelegate
extension WebSocketClient: URLSessionWebSocketDelegate {
    
    // 连接成功
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol1: String?) {
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 状态转换：只有从 Connecting 成功转换才有效
            if case .connecting = self.state {
                self.state = .connected
                self.startPing()
                self.onConnected?()
                self.trySendNext()
                DLLog("WebSocketClient: identifier=\(identifier) 连接成功")
            } else {
                DLLog("WebSocketClient: identifier=\(identifier) 连接成功后取消多余连接，从其他状态收到了 didOpen，说明有竞态，直接关闭这个多余的连接")
                // 如果从其他状态收到了 didOpen，说明有竞态，直接关闭这个多余的连接
                webSocketTask.cancel(with: .goingAway, reason: nil)
            }
        }
    }
    
    // 连接关闭
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                          didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // 运行时阶段的失效 (Close Code)
        // 处理 WebSocket 已经连上了，Token 过期了
        DispatchQueue.main.async { [weak self] in
            DLLog("WebSocketClient: identifier=\(self?.identifier ?? "") 连接关闭")
            // 你们后端定义 4001 为授权失效
            if closeCode.rawValue == 4001 {
                self?.onUnauthorized?()
                self?.performDisconnection(reason: WebSocketClientError.unauthorized)
            } else {
                self?.performDisconnection(reason: nil)
            }
        }
    }
}
