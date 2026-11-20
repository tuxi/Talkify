//
//  ConsolidatedCredentialVault.swift
//  Talkify
//
//  把一个 namespace 下的所有凭证合并存进**单条** login.keychain 条目。
//
//  背景：login.keychain 的授权是逐条目的。历史实现是每个 provider 一条
//  `llm/<id>` item，首次授权要弹 8 次；合并成一条后只需一次，且 Developer ID
//  签名下 ACL 以 team 为准，“始终允许”跨版本保留。
//
//  迁移：首次读取时若新条目不存在，则枚举 legacy service 的 account，逐条解密、
//  合并写入新条目，最后尽力删除 legacy 条目。迁移完成后不再读取 legacy。
//

import Foundation
import Security
import AgentKit
import CoreKit

final class ConsolidatedCredentialVault: CredentialStore, @unchecked Sendable {

    enum VaultError: Error, LocalizedError {
        case namespaceMismatch(expected: String, actual: String)
        case encodeFailed
        case writeFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .namespaceMismatch(let expected, let actual):
                "Credential target namespace \(actual) is not handled by this \(expected) vault."
            case .encodeFailed:
                "Unable to encode credentials."
            case .writeFailed(let status):
                "Unable to write credentials to Keychain (OSStatus \(status))."
            }
        }
    }

    /// 当前存储格式的版本；account 里带版本号，便于将来无歧义地再迁移。
    private let service: String
    private let account: String
    private let namespace: String
    private let legacyService: String?

    private let lock = NSLock()
    private var cached: CredentialMap?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String,
        account: String,
        namespace: String,
        legacyService: String? = nil
    ) {
        self.service = service
        self.account = account
        self.namespace = namespace
        self.legacyService = legacyService
    }

    // MARK: - CredentialStore

    func resolve(_ target: CredentialTarget) async throws -> Credential? {
        resolveSync(target)
    }

    func resolveSync(_ target: CredentialTarget) -> Credential? {
        guard target.namespace == namespace else { return nil }
        return load().entries[target]
    }

    func all() async throws -> CredentialMap {
        load()
    }

    func set(_ credential: Credential, for target: CredentialTarget) async throws {
        guard target.namespace == namespace else {
            throw VaultError.namespaceMismatch(expected: namespace, actual: target.namespace)
        }
        lock.lock()
        defer { lock.unlock() }

        var map = loadLocked()
        map[target] = credential
        try writeLocked(map)
        cached = map
    }

    func remove(_ target: CredentialTarget) async throws {
        guard target.namespace == namespace else {
            throw VaultError.namespaceMismatch(expected: namespace, actual: target.namespace)
        }
        lock.lock()
        defer { lock.unlock() }

        var map = loadLocked()
        guard map.entries[target] != nil else { return }
        map[target] = nil
        try writeLocked(map)
        cached = map
    }

    func clear() async throws {
        lock.lock()
        defer { lock.unlock() }

        deleteItem()
        cached = CredentialMap()
    }

    // MARK: - Loading / migration

    private func load() -> CredentialMap {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    private func loadLocked() -> CredentialMap {
        if let cached { return cached }

        switch readItem() {
        case .success(let map):
            cached = map
            return map

        case .missing:
            let migrated = migrateLegacyEntries()
            if !migrated.isEmpty {
                try? writeLocked(migrated)
            }
            cached = migrated
            return migrated

        case .failure:
            // 读失败（授权被拒、条目损坏等）时不要覆盖已有数据。
            cached = CredentialMap()
            return CredentialMap()
        }
    }

    private enum ReadOutcome {
        case success(CredentialMap)
        case missing
        case failure
    }

    private func readItem() -> ReadOutcome {
        let outcome: (status: OSStatus, value: Data?) = KeychainDiagnostics.measureRead(
            "credential_vault.read",
            service: service,
            account: account
        ) {
            var result: AnyObject?
            let status = SecItemCopyMatching(readQuery() as CFDictionary, &result)
            return (status: status, value: result as? Data)
        }

        switch outcome.status {
        case errSecSuccess:
            guard let data = outcome.value,
                  let map = try? decoder.decode(CredentialMap.self, from: data) else {
                KeychainDiagnostics.record(
                    "credential_vault.decode_failed",
                    service: service,
                    account: account
                )
                return .failure
            }
            return .success(map)
        case errSecItemNotFound:
            return .missing
        default:
            return .failure
        }
    }

    /// 把 legacy 的“一条一个 provider”迁移成单条 map。
    ///
    /// 迁移期间每条 legacy 条目仍然需要一次解密；在不匹配的签名身份上会各弹
    /// 一次。迁移成功写入新条目后，后续启动只读一条。
    private func migrateLegacyEntries() -> CredentialMap {
        guard let legacyService else { return CredentialMap() }

        let accounts = legacyAccounts(service: legacyService)
        guard !accounts.isEmpty else { return CredentialMap() }

        var map = CredentialMap()
        var succeededAccounts: [String] = []

        for account in accounts {
            guard let target = CredentialTarget(id: account) else { continue }

            let outcome: (status: OSStatus, value: String?) = KeychainDiagnostics.measureRead(
                "credential_vault.legacy_read",
                service: legacyService,
                account: account
            ) {
                var result: AnyObject?
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: legacyService,
                    kSecAttrAccount as String: account,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status: status, value: (result as? Data).flatMap { String(data: $0, encoding: .utf8) })
            }

            guard outcome.status == errSecSuccess,
                  let encoded = outcome.value,
                  let credential = try? decoder.decode(
                    Credential.self,
                    from: Data(encoded.utf8)
                  ) else {
                continue
            }

            map[target] = credential
            succeededAccounts.append(account)
        }

        if !map.isEmpty {
            KeychainDiagnostics.record(
                "credential_vault.migrated",
                service: service,
                account: account,
                details: [
                    "legacy_service": legacyService,
                    "legacy_accounts": String(accounts.count),
                    "migrated": String(map.entries.count),
                ]
            )
            // 写入成功后才删除旧条目；写入失败会保留旧数据，下个版本再试。
            do {
                try writeLocked(map)
                for account in succeededAccounts {
                    deleteLegacyItem(service: legacyService, account: account)
                }
            } catch {
                KeychainDiagnostics.record(
                    "credential_vault.migration_write_failed",
                    service: service,
                    account: account,
                    details: ["error": error.localizedDescription]
                )
            }
        }

        return map
    }

    /// 枚举 legacy service 的 account，只请求属性，不解密。
    private func legacyAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return [] }

        let rows: [[String: Any]]
        if let list = result as? [[String: Any]] {
            rows = list
        } else if let single = result as? [String: Any] {
            rows = [single]
        } else {
            rows = []
        }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func deleteLegacyItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let started = CFAbsoluteTimeGetCurrent()
        let status = SecItemDelete(query as CFDictionary)
        KeychainDiagnostics.record(
            "credential_vault.legacy_delete",
            service: service,
            account: account,
            status: status,
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000
        )
    }

    // MARK: - Writing

    private func writeLocked(_ map: CredentialMap) throws {
        guard let data = try? encoder.encode(map) else {
            throw VaultError.encodeFailed
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStarted = CFAbsoluteTimeGetCurrent()
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            updateAttributes as CFDictionary
        )
        KeychainDiagnostics.record(
            "credential_vault.update",
            service: service,
            account: account,
            status: updateStatus,
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - updateStarted) * 1000
        )

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw VaultError.writeFailed(updateStatus)
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStarted = CFAbsoluteTimeGetCurrent()
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        KeychainDiagnostics.record(
            "credential_vault.add",
            service: service,
            account: account,
            status: addStatus,
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - addStarted) * 1000
        )
        guard addStatus == errSecSuccess else {
            throw VaultError.writeFailed(addStatus)
        }
    }

    private func deleteItem() {
        let started = CFAbsoluteTimeGetCurrent()
        let status = SecItemDelete(baseQuery() as CFDictionary)
        KeychainDiagnostics.record(
            "credential_vault.delete",
            service: service,
            account: account,
            status: status,
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000
        )
    }

    // MARK: - Queries

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}
