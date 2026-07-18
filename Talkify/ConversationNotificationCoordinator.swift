//
//  ConversationNotificationCoordinator.swift
//  CodeAgent
//
//  Host-owned local notifications for AgentKit multi-session attention.
//

import Foundation
import Observation
import UserNotifications
import AgentKit

@MainActor
@Observable
final class ConversationNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private(set) var pendingSessionID: String?

    private let center: UNUserNotificationCenter

    override init() {
        self.center = .current()
        super.init()
        center.delegate = self
    }

    func handle(_ event: ConversationAttentionEvent) {
        Task { await deliver(event) }
    }

    func consumePendingSessionID(_ sessionID: String) {
        guard pendingSessionID == sessionID else { return }
        pendingSessionID = nil
    }

    private func deliver(_ event: ConversationAttentionEvent) async {
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        let canDeliver: Bool
        #if os(iOS)
        canDeliver = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        #else
        canDeliver = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        #endif
        guard canDeliver else { return }

        let notification = notificationContent(for: event)
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: notification.content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func notificationContent(
        for event: ConversationAttentionEvent
    ) -> (identifier: String, content: UNMutableNotificationContent) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        let sessionID: String
        let turnID: String?
        let sequence: Int64

        switch event {
        case .approvalRequired(let id, let turn, let pendingCount, let seq):
            sessionID = id
            turnID = turn
            sequence = seq
            content.title = "Code Agent 需要审批"
            content.body = pendingCount > 1
                ? "后台任务有 \(pendingCount) 项操作等待你的决定。"
                : "后台任务有一项操作等待你的决定。"

        case .turnCompleted(let attention):
            sessionID = attention.sessionID
            turnID = attention.turnID
            sequence = attention.sequence
            switch attention.outcome {
            case .succeeded:
                content.title = "Code Agent 已完成"
                content.body = "后台任务已完成，点击查看结果。"
            case .failed:
                content.title = "Code Agent 执行失败"
                content.body = "后台任务执行失败，点击查看详情。"
            case .cancelled:
                content.title = "Code Agent 已取消"
                content.body = "后台任务已取消。"
            }
        }

        content.threadIdentifier = sessionID
        content.userInfo = [
            "session_id": sessionID,
            "turn_id": turnID ?? "",
            "sequence": String(sequence),
        ]
        return (
            "conversation-attention.\(sessionID).\(sequence)",
            content
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.content.userInfo["session_id"] as? String
        if let sessionID, !sessionID.isEmpty {
            Task { @MainActor [weak self] in
                self?.pendingSessionID = sessionID
            }
        }
        completionHandler()
    }
}
