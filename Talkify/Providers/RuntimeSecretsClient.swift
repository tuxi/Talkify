//
//  RuntimeSecretsClient.swift
//  Talkify
//
//  Minimal POST /v1/secrets client for the codeagentd daemon (A2 secrets push).
//
//  The daemon's POST /v1/secrets (Bearer-authed) updates its mutable injected
//  resolver; the next GET /v1/runtime/models rebuilds the catalog with the
//  injected credentials, so models become available without a restart.
//
//  Body shape: `{"<namespace>/<name>": {"type":"bearer","secret":"..."}}`.
//
//  AgentKit does not yet expose POST /v1/secrets, so chater owns this small
//  client (mirrors how RuntimeHTTPClient talks to the runtime control plane).
//

import Foundation

/// One credential entry in the POST /v1/secrets body.
struct RuntimeSecretsBodyEntry: Codable, Sendable, Equatable {
    let type: String
    let secret: String

    init(type: String, secret: String) {
        self.type = type
        self.secret = secret
    }
}

enum RuntimeSecretsClientError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Secrets 推送响应无效。"
        case .httpStatus(let code):
            return "Runtime 错误 (HTTP \(code))"
        }
    }
}

struct RuntimeSecretsClient: Sendable {
    let baseURL: URL
    let token: String

    /// POST /v1/secrets — replaces/updates the daemon's injected credential resolver.
    func push(_ entries: [String: RuntimeSecretsBodyEntry]) async throws {
        let url = baseURL.appendingPathComponent("v1/secrets")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(entries)
        request.timeoutInterval = 15

        let session = URLSession(
            configuration: .ephemeral,
            delegate: SecretsLoopbackTLSAcceptingDelegate(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RuntimeSecretsClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RuntimeSecretsClientError.httpStatus(http.statusCode)
        }
    }
}

/// Accepts self-signed TLS on loopback (mirror of CodeAgentDaemon's delegate).
private final class SecretsLoopbackTLSAcceptingDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              challenge.protectionSpace.host == "127.0.0.1" || challenge.protectionSpace.host == "localhost"
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
