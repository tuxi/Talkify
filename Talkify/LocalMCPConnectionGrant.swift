#if os(macOS)
import Foundation
import Darwin

enum LocalMCPGrantError: Error, LocalizedError {
    case unavailable, invalidIdentity, unsafeFile, writeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "当前本地 Runtime 不可用或认证失败。"
        case .invalidIdentity: "无法验证当前 Runtime 身份或 TLS 连接。"
        case .unsafeFile: "MCP 连接文件必须位于当前用户独占的私有目录中。"
        case .writeFailed: "无法保存或撤销 MCP 连接文件。"
        }
    }
}

/// Secret-bearing local handoff. Never put this value in UI, logs, clipboard,
/// MCP output, command arguments, or Codex configuration.
struct LocalMCPConnectionGrant: Codable {
    let schemaVersion: Int
    let endpoint: String
    let serverID: String
    let storeID: String?
    let instanceID: String
    let daemonPID: Int32
    let expiresAt: String
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", endpoint
        case serverID = "server_id", storeID = "store_id"
        case instanceID = "instance_id", daemonPID = "daemon_pid"
        case expiresAt = "expires_at", accessToken = "access_token"
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talkify/CodeAgentMCP", isDirectory: true)
            .resolvingSymlinksInPath()
    }

    static func identity(endpoint: URL, token: String) async throws -> (serverID: String, storeID: String?) {
        guard ["http", "https"].contains(endpoint.scheme ?? ""),
              ["127.0.0.1", "[::1]", "::1"].contains(endpoint.host ?? ""),
              endpoint.port != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.isEmpty || endpoint.path == "/" else {
            throw LocalMCPGrantError.invalidIdentity
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config, delegate: MCPNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func get(_ path: String, allowMissing: Bool = false) async throws -> [String: Any]? {
            var request = URLRequest(url: endpoint.appendingPathComponent(path))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch { throw LocalMCPGrantError.invalidIdentity }
            guard let http = response as? HTTPURLResponse else { throw LocalMCPGrantError.invalidIdentity }
            if allowMissing && http.statusCode == 404 { return nil }
            guard http.statusCode == 200, data.count <= 65536,
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (envelope["code"] as? Int) == 0,
                  let value = envelope["data"] as? [String: Any] else {
                throw LocalMCPGrantError.unavailable
            }
            return value
        }
        guard let info = try await get("v1/runtime/info"),
              let serverID = info["server_id"] as? String, !serverID.isEmpty else {
            throw LocalMCPGrantError.invalidIdentity
        }
        let tasks = try await get("v1/tasks/capabilities", allowMissing: true)
        if let tasks {
            guard tasks["server_id"] as? String == serverID,
                  let storeID = tasks["store_id"] as? String, !storeID.isEmpty else {
                throw LocalMCPGrantError.invalidIdentity
            }
            return (serverID, storeID)
        }
        return (serverID, nil)
    }

    /// Dedicated application-owned file, atomically replaced after explicit
    /// authorization. Existing symlinks, public files and unknown files fail closed.
    func save(in directory: URL = Self.directory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let dfd = try Self.openDirectory(directory)
        defer { Darwin.close(dfd) }
        var old = stat()
        if fstatat(dfd, "connection.json", &old, AT_SYMLINK_NOFOLLOW) == 0 {
            let existing = try Self.read(dfd: dfd)
            guard existing.schemaVersion == 1 else { throw LocalMCPGrantError.unsafeFile }
        } else if errno != ENOENT { throw LocalMCPGrantError.unsafeFile }
        let name = ".grant-\(UUID().uuidString).tmp"
        let fd = openat(dfd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LocalMCPGrantError.writeFailed }
        defer { Darwin.close(fd); unlinkat(dfd, name, 0) }
        let data = try JSONEncoder().encode(self)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw LocalMCPGrantError.writeFailed }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(dfd, name, dfd, "connection.json") == 0 else {
            throw LocalMCPGrantError.writeFailed
        }
        return directory.appendingPathComponent("connection.json")
    }

    static func revoke(at url: URL, instanceID: String) throws {
        let dfd = try openDirectory(url.deletingLastPathComponent())
        defer { Darwin.close(dfd) }
        guard try read(dfd: dfd).instanceID == instanceID else { throw LocalMCPGrantError.unsafeFile }
        guard unlinkat(dfd, "connection.json", 0) == 0 else { throw LocalMCPGrantError.writeFailed }
    }

    private static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else {
            throw LocalMCPGrantError.unsafeFile
        }
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw LocalMCPGrantError.unsafeFile }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_uid == geteuid(), st.st_mode & 0o7777 == 0o700 else {
            Darwin.close(fd)
            throw LocalMCPGrantError.unsafeFile
        }
        return fd
    }

    private static func read(dfd: Int32) throws -> Self {
        let fd = openat(dfd, "connection.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw LocalMCPGrantError.unsafeFile }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_uid == geteuid(), st.st_mode & S_IFMT == S_IFREG,
              st.st_mode & 0o7777 == 0o600, st.st_nlink == 1, st.st_size <= 16384,
              let data = try file.read(upToCount: 16385),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            throw LocalMCPGrantError.unsafeFile
        }
        return value
    }
}

private final class MCPNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
