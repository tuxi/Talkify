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
    private(set) var pendingConversation: RuntimeConversationIdentity?

    private let center: UNUserNotificationCenter

    override init() {
        self.center = .current()
        super.init()
        center.delegate = self
    }

    func handle(
        _ event: ConversationAttentionEvent,
        serverConnectionID: String
    ) {
        Task {
            await deliver(event, serverConnectionID: serverConnectionID)
        }
    }

    func consumePendingConversation(_ identity: RuntimeConversationIdentity) {
        guard pendingConversation == identity else { return }
        pendingConversation = nil
    }

    private func deliver(
        _ event: ConversationAttentionEvent,
        serverConnectionID: String
    ) async {
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

        let notification = notificationContent(
            for: event,
            serverConnectionID: serverConnectionID
        )
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: notification.content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func notificationContent(
        for event: ConversationAttentionEvent,
        serverConnectionID: String
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
                ? String(format: TalkifyLocalized.string("agent.notification.pending_items_many"), "\(pendingCount)")
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

        content.threadIdentifier = "\(serverConnectionID).\(sessionID)"
        content.userInfo = [
            "server_connection_id": serverConnectionID,
            "session_id": sessionID,
            "turn_id": turnID ?? "",
            "sequence": String(sequence),
        ]
        return (
            "conversation-attention.\(serverConnectionID).\(sessionID).\(sequence)",
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
        let serverConnectionID = response.notification.request.content
            .userInfo["server_connection_id"] as? String
        if let sessionID, !sessionID.isEmpty,
           let serverConnectionID, !serverConnectionID.isEmpty {
            Task { @MainActor [weak self] in
                self?.pendingConversation = RuntimeConversationIdentity(
                    serverConnectionID: serverConnectionID,
                    conversationID: sessionID
                )
            }
        }
        completionHandler()
    }
}
