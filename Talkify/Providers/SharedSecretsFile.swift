//
//  SharedSecretsFile.swift
//  Talkify
//
//  Writes the shared credential file ~/.codeagent/secrets.json consumed by the
//  runtime CLI/TUI (a separate process from the app's daemon). The app's A2
//  POST /v1/secrets to the daemon is separate and stays untouched.
//
//  File format (runtime SecretsFile.Load):
//    { "llm/qwen": {"type":"bearer","secret":"sk-..."}, ... }
//  Keys are "llm/<provider-id>"; the runtime only consumes "llm/" entries.
//
//  Write is atomic (temp file + rename) with 0600 permissions. Read-merge-write
//  preserves other namespaces written by other apps.
//

import Foundation
import AgentKit
import OSLog

private let sharedSecretsLogger = Logger(subsystem: "com.objc.chat", category: "SharedSecrets")

/// One credential entry in the shared secrets file (same shape as the A2 body).
struct SharedSecretsBodyEntry: Codable, Sendable, Equatable {
    let type: String
    let secret: String
}

enum SharedSecretsFile {
    /// Absolute URL of `~/.codeagent/secrets.json`.
    static var secretsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeagent")
            .appendingPathComponent("secrets.json")
    }

    /// Extract the llm/* bearer credentials from a CredentialMap into the
    /// shared wire shape. Optionally scoped to a single target.
    static func llmEntries(
        from map: CredentialMap,
        only target: CredentialTarget? = nil
    ) -> [String: SharedSecretsBodyEntry] {
        var entries: [String: SharedSecretsBodyEntry] = [:]
        for (credentialTarget, credential) in map.entries {
            guard credentialTarget.namespace == "llm",
                  credential.kind == .bearer,
                  !credential.secret.isEmpty else { continue }
            if let target, credentialTarget != target { continue }
            entries["llm/\(credentialTarget.name)"] = SharedSecretsBodyEntry(
                type: "bearer",
                secret: credential.secret
            )
        }
        return entries
    }

    /// Write the shared secrets file atomically with 0600 permissions.
    /// Read-merge-write: existing keys (other namespaces) are preserved, the
    /// llm/* entries are brought current.
    static func write(entries: [String: SharedSecretsBodyEntry]) throws {
        let directory = secretsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Read-merge: preserve whatever is already on disk (other apps may have
        // written other namespaces), then overlay current llm/* entries.
        var merged: [String: SharedSecretsBodyEntry] = [:]
        if let existing = try? Data(contentsOf: secretsFileURL),
           let decoded = try? JSONDecoder().decode(
               [String: SharedSecretsBodyEntry].self,
               from: existing
           ) {
            merged = decoded
        }
        for (key, value) in entries {
            merged[key] = value
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(merged)

        // Atomic write: temp file in the same directory + rename.
        let tempURL = directory.appendingPathComponent(
            "secrets.json.tmp-\(UUID().uuidString)"
        )
        try data.write(to: tempURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tempURL.path
        )
        try FileManager.default.replaceItemAt(
            secretsFileURL,
            withItemAt: tempURL
        )
    }
}
