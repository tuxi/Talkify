//
//  KeychainDiagnostics.swift
//  CoreKit
//
//  钥匙串访问诊断日志。
//
//  背景：macOS Direct 版（非沙盒）把机密存在 login.keychain，每个条目带一份
//  ACL（允许哪些 App 解密）。二进制签名不在 ACL 里时，系统会要求输入登录钥匙串
//  密码。为了定位“首次启动为什么弹很多次”，这里记录：
//    - 当前进程的签名身份（bundle id / cdhash / team / 可执行路径）
//    - 每次钥匙串读取的 service / account / OSStatus / 耗时
//    - 启动时各 service 的条目数量（只查属性，不解密，不会触发弹窗）
//
//  日志里**不包含任何密钥值**。写入位置：
//    ~/Library/Logs/Talkify/keychain-diagnostics.jsonl
//  可用环境变量 TALKIFY_KEYCHAIN_DIAG=0 关闭。
//

import Foundation
import Security
import OSLog

public enum KeychainDiagnostics {

    // MARK: - Configuration

    /// 默认只在 Debug 构建开启；Release 需要显式 `TALKIFY_KEYCHAIN_DIAG=1`。
    ///
    /// Release 默认关闭是为了避免在用户目录长期写诊断文件；排查 ACL 弹窗时
    /// 临时加环境变量启动即可。
    public static var isEnabled: Bool {
        switch ProcessInfo.processInfo.environment["TALKIFY_KEYCHAIN_DIAG"] {
        case "1":
            return true
        case "0":
            return false
        default:
            return _isDebugAssertConfiguration()
        }
    }

    private static let logger = Logger(
        subsystem: "com.objc.chat",
        category: "KeychainDiagnostics"
    )

    private static let queue = DispatchQueue(
        label: "com.objc.chat.keychain-diagnostics"
    )

    private static let maxLogBytes = 4 * 1024 * 1024

    private static let logFileName = "keychain-diagnostics.jsonl"

    // MARK: - Event recording

    /// 记录一条事件（单行 JSON）。耗时单位毫秒。
    public static func record(
        _ event: String,
        service: String? = nil,
        account: String? = nil,
        status: OSStatus? = nil,
        durationMilliseconds: Double? = nil,
        details: [String: String] = [:]
    ) {
        guard isEnabled else { return }

        var fields: [String: Any] = [
            "event": event,
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        if let service { fields["service"] = service }
        if let account { fields["account"] = account }
        if let status {
            fields["status"] = Int(status)
            fields["statusText"] = statusText(status)
        }
        if let durationMilliseconds {
            fields["duration_ms"] = (durationMilliseconds * 1000).rounded() / 1000
        }
        if !details.isEmpty {
            fields["details"] = details
        }
        append(fields)
    }

    /// 包装一次钥匙串读取：记录 OSStatus 与耗时，并原样返回结果。
    public static func measureRead<T>(
        _ event: String,
        service: String?,
        account: String?,
        details: [String: String] = [:],
        _ body: () -> (status: OSStatus, value: T)
    ) -> (status: OSStatus, value: T) {
        let started = CFAbsoluteTimeGetCurrent()
        let result = body()
        record(
            event,
            service: service,
            account: account,
            status: result.status,
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000,
            details: details
        )
        return result
    }

    // MARK: - Process identity

    private static let identityLock = NSLock()
    nonisolated(unsafe) private static var cachedIdentity: [String: String]?

    /// 当前进程签名身份。用于判断 ACL 为什么匹配/不匹配。
    public static func processIdentity() -> [String: String] {
        identityLock.lock()
        defer { identityLock.unlock() }
        if let cachedIdentity { return cachedIdentity }

        var identity: [String: String] = [
            "process": ProcessInfo.processInfo.processName,
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "bundle_path": Bundle.main.bundlePath,
            "executable": CommandLine.arguments.first ?? "",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]

        #if os(macOS)
        var code: SecCode?
        var staticCode: SecStaticCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
           let staticCode {
            var information: CFDictionary?
            let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
            if SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
               let information = information as? [String: Any] {
                if let unique = information[kSecCodeInfoUnique as String] as? Data {
                    identity["cdhash"] = unique.map { String(format: "%02x", $0) }.joined()
                }
                if let team = information[kSecCodeInfoTeamIdentifier as String] as? String {
                    identity["team_id"] = team
                }
                if let identifier = information[kSecCodeInfoIdentifier as String] as? String {
                    identity["signing_identifier"] = identifier
                }
            }
        } else {
            identity["cdhash"] = "unsigned"
        }

        if let translated = isTranslated() {
            identity["rosetta_translated"] = translated ? "1" : "0"
        }
        #endif

        cachedIdentity = identity
        return identity
    }

    /// 启动时记录一次进程身份，便于对齐另一台机器上的日志。
    public static func logProcessIdentity(trigger: String) {
        guard isEnabled else { return }
        var details = processIdentity()
        details["trigger"] = trigger
        append([
            "event": "process.identity",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "details": details,
        ])
    }

    // MARK: - Data protection keychain probe

    /// 一次性探测：当前签名身份能否使用 Data Protection Keychain
    /// （`kSecUseDataProtectionKeychain`）。该模式下访问由签名 + access group
    /// 决定，不会出现 login.keychain 的 ACL 密码框。
    ///
    /// 只由 `TALKIFY_KEYCHAIN_PROBE=1` 触发；自建自删一个假条目，不读写真实数据。
    /// 结果写入 `keychain.probe.data_protection` 事件：
    ///   addStatus == 0  → 可以迁移
    ///   addStatus == -34018 (errSecMissingEntitlement) → 该签名身份不可用，需要
    ///   走“合并条目/减少弹窗”的路线
    public static func probeDataProtectionKeychainIfRequested() {
        guard isEnabled,
              ProcessInfo.processInfo.environment["TALKIFY_KEYCHAIN_PROBE"] == "1" else {
            return
        }

        let service = "com.objc.chat.keychain-probe"
        let account = "dp-probe"

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let staleDeleteStatus = SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data("probe".utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStarted = CFAbsoluteTimeGetCurrent()
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        let addDuration = (CFAbsoluteTimeGetCurrent() - addStarted) * 1000

        var readQuery = baseQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        let readOutcome = measureRead(
            "keychain.probe.data_protection.read",
            service: service,
            account: account
        ) {
            let status = SecItemCopyMatching(readQuery as CFDictionary, nil)
            return (status: status, value: status)
        }
        let readStatus = readOutcome.value

        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)

        var details: [String: String] = [
            "add": String(addStatus),
            "addText": statusText(addStatus),
            "read": String(readStatus),
            "readText": statusText(readStatus),
            "delete": String(deleteStatus),
            "stale_delete": String(staleDeleteStatus),
        ]
        if let cdhash = processIdentity()["cdhash"] {
            details["cdhash"] = cdhash
        }

        record(
            "keychain.probe.data_protection",
            service: service,
            account: account,
            status: addStatus,
            durationMilliseconds: addDuration,
            details: details
        )
    }

    // MARK: - Inventory

    /// 统计某 service（或某 account）下的条目数。
    ///
    /// 只请求属性（`kSecReturnAttributes`），不请求数据，因此不会触发 ACL 解密，
    /// 也就不会弹密码框。
    public static func itemCount(service: String? = nil, account: String? = nil) -> Int {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if let service { query[kSecAttrService as String] = service }
        if let account { query[kSecAttrAccount as String] = account }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let rows = result as? [[String: Any]] { return rows.count }
            return result == nil ? 0 : 1
        case errSecItemNotFound:
            return 0
        default:
            return -1
        }
    }

    /// 启动时把所有相关 service/account 的条目数记一条，弹窗次数应与之对应。
    public static func logInventory(services: [String], accounts: [String]) {
        guard isEnabled else { return }

        var counts: [String: Int] = [:]
        for service in services {
            counts["service:\(service)"] = itemCount(service: service)
        }
        for account in accounts {
            counts["account:\(account)"] = itemCount(account: account)
        }
        let total = counts.values.filter { $0 > 0 }.reduce(0, +)

        append([
            "event": "keychain.inventory",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "details": [
                "counts": counts.mapValues(String.init),
                "present_total": String(total),
            ],
        ])
    }

    // MARK: - Log location

    /// 日志文件路径（不存在时返回 nil）。
    public static func logFileURL() -> URL? {
        guard let url = logURL else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Private

    nonisolated(unsafe) private static var didPrepareFile = false

    private static var logURL: URL? {
        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Talkify", isDirectory: true)
            .appendingPathComponent(logFileName)
    }

    private static func append(_ fields: [String: Any]) {
        var record = fields
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        record["timestamp"] = formatter.string(from: Date())

        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(
                withJSONObject: record,
                options: [.sortedKeys]
              ) else {
            return
        }

        let line = data + Data([0x0A])

        queue.sync {
            guard let url = logURL else {
                logger.debug("keychain diagnostics: no log directory available")
                return
            }
            prepareFileIfNeeded(at: url)

            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }

        if let message = String(data: data, encoding: .utf8) {
            logger.debug("\(message, privacy: .public)")
        }
    }

    private static func prepareFileIfNeeded(at url: URL) {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()

        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        if !manager.fileExists(atPath: url.path) {
            manager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }

        guard !didPrepareFile else { return }
        didPrepareFile = true

        // 单文件上限，避免长期运行无限增长；只保留上一份。
        if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > maxLogBytes {
            let rotated = url.appendingPathExtension("old")
            try? manager.removeItem(at: rotated)
            try? manager.moveItem(at: url, to: rotated)
            manager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
    }

    private static func statusText(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }

    #if os(macOS)
    private static func isTranslated() -> Bool? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0)
        guard result == 0 else { return nil }
        return value == 1
    }
    #endif
}
