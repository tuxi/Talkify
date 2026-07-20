import Foundation
import AgentKit

/// Decorates AgentKit's frozen local-state store solely to reclaim host-owned
/// files when an attachment leaves a draft (accepted or explicitly deleted).
final class ManagedUserAssetLocalStateStore: ConversationLocalStateStore, @unchecked Sendable {
    private let underlying: any ConversationLocalStateStore
    private let fileStore: ManagedUserAssetFileStore
    private let lock = NSRecursiveLock()

    init(
        underlying: any ConversationLocalStateStore = SQLiteConversationLocalStateStore.shared,
        fileStore: ManagedUserAssetFileStore
    ) {
        self.underlying = underlying
        self.fileStore = fileStore
    }

    func state(for key: ConversationLocalStateKey) throws -> ConversationLocalState? {
        try underlying.state(for: key)
    }

    func save(_ state: ConversationLocalState, for key: ConversationLocalStateKey) throws {
        lock.lock(); defer { lock.unlock() }
        let previous = try underlying.state(for: key)
        try underlying.save(state, for: key)
        reclaimRemoved(from: previous, to: state)
    }

    func updateState(
        for key: ConversationLocalStateKey,
        _ update: @Sendable (inout ConversationLocalState) -> Void
    ) throws {
        lock.lock(); defer { lock.unlock() }
        let previous = try underlying.state(for: key)
        try underlying.updateState(for: key, update)
        let current = try underlying.state(for: key)
        reclaimRemoved(from: previous, to: current)
    }

    func latestDraft() throws -> (id: UUID, state: ConversationLocalState)? {
        try underlying.latestDraft()
    }

    func migrateDraft(_ draftID: UUID, to sessionID: String) throws {
        try underlying.migrateDraft(draftID, to: sessionID)
    }

    func removeState(for key: ConversationLocalStateKey) throws {
        lock.lock(); defer { lock.unlock() }
        let previous = try underlying.state(for: key)
        try underlying.removeState(for: key)
        reclaimRemoved(from: previous, to: nil)
    }

    func flush() throws { try underlying.flush() }
    var hasEstablishedAttentionBaseline: Bool { underlying.hasEstablishedAttentionBaseline }
    func establishAttentionBaseline() throws { try underlying.establishAttentionBaseline() }

    private func reclaimRemoved(
        from previous: ConversationLocalState?,
        to current: ConversationLocalState?
    ) {
        let currentIDs = Set(current?.composerDraft.attachments.map(\.id) ?? [])
        for attachment in previous?.composerDraft.attachments ?? [] where !currentIDs.contains(attachment.id) {
            fileStore.removeAttachmentFiles(referencedBy: attachment.resourceURI)
        }
    }
}
