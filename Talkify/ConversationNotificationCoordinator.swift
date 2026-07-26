//
//  ConversationNotificationCoordinator.swift
//  Talkify
//
//  Host-owned local notifications for AgentKit multi-session attention.
//

import Foundation
import Observation
import UserNotifications
import AgentKit
import CoreKit

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
            content.title = TalkifyLocalized.string("agent.notification.approval_needed")
            content.body = pendingCount > 1
                ? String(format: TalkifyLocalized.string("agent.notification.pending_items_many"), pendingCount)
                : TalkifyLocalized.string("agent.notification.pending_items_one")

        case .turnCompleted(let attention):
            sessionID = attention.sessionID
            turnID = attention.turnID
            sequence = attention.sequence
            switch attention.outcome {
            case .succeeded:
                content.title = TalkifyLocalized.string("agent.notification.completed")
                content.body = TalkifyLocalized.string("agent.notification.completed_body")
            case .failed:
                content.title = TalkifyLocalized.string("agent.notification.failed")
                content.body = TalkifyLocalized.string("agent.notification.failed_body")
            case .cancelled:
                content.title = TalkifyLocalized.string("agent.notification.cancelled")
                content.body = TalkifyLocalized.string("agent.notification.cancelled_body")
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
