#if os(macOS)
import Foundation
import Security
import OSLog
import CoreKit

/// Manages the `codeagentd` child process lifecycle on macOS Direct distribution.
///
/// The daemon binary is bundled at `Contents/Resources/codeagentd`. It is launched
/// as an independent process with a login-shell PATH so tools like `go`, `node`,
/// and `brew` are discoverable without workarounds.
///
/// Communication with the daemon uses HTTP/WebSocket on loopback — the same
/// agent-wire protocol as the embedded gomobile runtime. AgentKit's
/// `RuntimeHTTPClient` and `RuntimeServerCoordinator` are reused unchanged.
@MainActor
final class CodeAgentDaemon: @unchecked Sendable {
    static let shared = CodeAgentDaemon()

    /// Preferred loopback port. If the port is in use the daemon will bind
    /// an OS-assigned ephemeral port (via `127.0.0.1:0`) and we discover it
    /// from the port-file written by `--port-file`.
    private static let preferredPort = 18797

    private let logger = Logger(subsystem: "com.objc.chat", category: "Daemon")

    // MARK: - State

    private var process: Process?
    private var portFileURL: URL?
    private var mcpGrantURL: URL?
    private var mcpInstanceID = UUID().uuidString
    private var startTask: Task<Void, Error>?
    private var startTaskID: UUID?
    private var startupProgress = "launching"
    private var requiresIndexMigration = false
    private var shellEnvironment: [String: String]?
    /// The host must register the new ephemeral endpoint and access token after
    /// a crash. Restarting just the child leaves clients on a dead connection.
    var onRestartNeeded: (@MainActor () async -> Void)?

    /// The runtime access token generated for this daemon session. A fresh
    /// 256-bit random token is created each time the daemon starts, matching
    /// the pattern used by `EmbeddedRuntimeAccessToken`.
    private(set) var accessToken: String = ""

    /// PID of the running daemon process, or -1 if not running.
    var processID: Int32 { process?.processIdentifier ?? -1 }

    /// The actual TCP port the daemon is listening on, resolved after start.
    private(set) var port: Int = 0

    /// Whether the daemon is using TLS (HTTPS). Detected automatically
    /// during the first health check.
    private(set) var usesTLS: Bool = false

    /// HTTP base URL for the daemon's API, resolved after start.
    var endpoint: URL? {
        guard port > 0 else { return nil }
        return URL(string: "\(usesTLS ? "https" : "http")://127.0.0.1:\(port)")
    }

    var isRunning: Bool {
        guard let process else { return false }
        return process.isRunning
    }

    // MARK: - Binary location

    /// Absolute path to the bundled `codeagentd` binary.
    var daemonURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("codeagentd")
    }

    // MARK: - Start / Stop

    /// Launch the daemon and wait for it to become ready.
    func start() async throws {
        if let startTask {
            try await startTask.value
            return
        }
        if isRunning && port > 0 { return }
        let taskID = UUID()
        let task = Task { try await self.launch() }
        startTask = task
        startTaskID = taskID
        defer {
            if startTaskID == taskID {
                startTask = nil
                startTaskID = nil
            }
        }
        try await task.value
    }

    private func launch() async throws {
        let startedAt = ProcessInfo.processInfo.systemUptime
        startupProgress = "preparing process"
        requiresIndexMigration = false
        usesTLS = false
        guard let daemonURL else {
            throw CodeAgentDaemonError.binaryNotFound
        }

        // Kill any stale daemon left over from a previous run.
        stopRunningProcess()
        await killExistingDaemons()
        try Task.checkCancellation()

        // Generate fresh 256-bit access token
        accessToken = generateAccessToken()
        mcpInstanceID = UUID().uuidString

        // Create a temporary port-file for the daemon to report its actual port
        let portFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeagentd-\(UUID().uuidString).port")
        portFileURL = portFile
        // Remove any stale file
        try? FileManager.default.removeItem(at: portFile)

        let process = Process()
        process.executableURL = daemonURL
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Build the environment from the user's login shell. This picks up
        // API keys (DEEPSEEK_API_KEY, etc.) that codeagentd needs for
        // credential.source=env models, plus the full PATH.
        var env: [String: String]
        if let shellEnvironment {
            env = shellEnvironment
        } else {
            env = await resolveUserShellEnvironment()
            shellEnvironment = env
        }
        try Task.checkCancellation()
        traceStartup("environment ready", since: startedAt)
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["CODEAGENT_SERVER_ACCESS_TOKEN"] = accessToken
        env["CODEAGENT_MCP_INHERIT_CLAUDE"] = "1"
#if DEBUG
        // The GUI's Xcode environment is separate from the login shell used
        // above. One debug opt-in enables both the panel and its child runtime.
        let debugEnvironment = ProcessInfo.processInfo.environment
        if debugEnvironment["TALKIFY_DEBUG_TEXT_SUPPLEMENTS"] == "1" {
            env["CODEAGENT_EXPERIMENTAL_TEXT_SUPPLEMENTS"] = "1"
        } else if let value = debugEnvironment["CODEAGENT_EXPERIMENTAL_TEXT_SUPPLEMENTS"] {
            env["CODEAGENT_EXPERIMENTAL_TEXT_SUPPLEMENTS"] = value
        }
#endif
        process.environment = env

        // Request an ephemeral port so we never collide.
        // Must use --port-file=PATH (with =) — the daemon expects the value
        // attached to the flag name, not as a separate argument.
        process.arguments = ["--port-file=\(portFile.path)", "127.0.0.1:0"]

        // Capture stderr for diagnostics (daemon writes control-plane, worktree
        // reconciliation, and error messages to stderr).
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.count > 0,
                  let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.process === process else { return }
                if line.contains("[startup]") {
                    self.startupProgress = line
                    if line.contains("phase=sqlite_index"), line.contains("started") {
                        self.requiresIndexMigration = true
                    }
                    self.logger.info("daemon: \(line, privacy: .public)")
                } else {
                    self.logger.debug("daemon: \(line, privacy: .public)")
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(pid: proc.processIdentifier, status: proc.terminationStatus, reason: proc.terminationReason)
            }
        }

        try process.run()
        self.process = process

        logger.info("Launched codeagentd (pid: \(process.processIdentifier))")

        // Wait for the port-file to be written by the daemon, or timeout
        do {
            port = try await waitForPortFile(at: portFile, timeout: 100)
        } catch {
            traceStartup("failed: \(startupProgress)", since: startedAt)
            throw error
        }
        traceStartup("port ready: \(port)", since: startedAt)
    }

    /// Gracefully shut down the daemon. Sends SIGTERM, waits briefly, then
    /// escalates to SIGKILL if the process is still alive.
    func stop() {
        startTask?.cancel()
        startTask = nil
        startTaskID = nil
        stopRunningProcess()
    }

    private func stopRunningProcess() {
        try? revokeMCPConnection()
        guard let process else { return }

        logger.info("Stopping codeagentd (pid: \(process.processIdentifier))")

        process.terminationHandler = nil // Don't trigger crash recovery
        if process.isRunning { process.terminate() } // SIGTERM

        // Give it 3 seconds for graceful shutdown, then force-kill
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(3)) {
            var killed = false
            if process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
                killed = true
            }
            if killed {
                self.logger.warning("codeagentd force-killed after timeout")
            }
        }
        // Process.waitUntilExit() blocks the MainActor and freezes the app.
        // The captured Process above remains alive until the bounded cleanup.
        self.process = nil
        self.port = 0

        // Clean up port-file
        if let url = portFileURL {
            try? FileManager.default.removeItem(at: url)
            portFileURL = nil
        }
    }

    // MARK: - Health check

    /// Check if the daemon HTTP server is responding.
    /// Auto-detects TLS: tries HTTPS first (the daemon may have TLS enabled
    /// from ~/.codeagent/settings.json), then falls back to plain HTTP.
    func checkHealth() async -> Bool {
        guard port > 0 else { return false }

        // Build URLs for HTTPS and HTTP
        let httpsURL = URL(string: "https://127.0.0.1:\(port)/healthz")!
        let httpURL = URL(string: "http://127.0.0.1:\(port)/healthz")!

        let urls = usesTLS ? [httpsURL] : [httpsURL, httpURL]

        for url in urls {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 3
                let (data, response) = try await urlSession().data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let body = String(data: data, encoding: .utf8)?
                          .trimmingCharacters(in: .whitespacesAndNewlines),
                      body == "ok" else { continue }
                // Remember the scheme that worked
                usesTLS = (url.scheme == "https")
                return true
            } catch {
                continue
            }
        }
        return false
    }

    /// URLSession that accepts self-signed certificates on loopback.
    /// The daemon may use TLS with a self-signed cert from
    /// ~/.codeagent/tls/. On loopback this is safe.
    private func urlSession() -> URLSession {
        let delegate = LoopbackTLSAcceptingDelegate()
        return URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    /// Wait for the daemon to respond to health checks.
    func waitForReady(timeout: TimeInterval = 10.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await checkHealth() {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw CodeAgentDaemonError.healthCheckTimeout
    }

    // MARK: - Explicit local MCP connection grant

    func exportMCPConnection() async throws -> URL {
        guard isRunning, let endpoint, !accessToken.isEmpty else {
            throw LocalMCPGrantError.unavailable
        }
        let pid = processID
        let instance = mcpInstanceID
        let token = accessToken
        let identity = try await LocalMCPConnectionGrant.identity(endpoint: endpoint, token: token)
        guard isRunning, processID == pid, mcpInstanceID == instance,
              self.endpoint == endpoint, accessToken == token else {
            throw LocalMCPGrantError.unavailable
        }
        let grant = LocalMCPConnectionGrant(
            schemaVersion: 1, endpoint: endpoint.absoluteString,
            serverID: identity.serverID, storeID: identity.storeID,
            instanceID: instance, daemonPID: pid,
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(12 * 3600)),
            accessToken: token
        )
        let url = try grant.save()
        mcpGrantURL = url
        return url
    }

    func revokeMCPConnection() throws {
        guard let url = mcpGrantURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try LocalMCPConnectionGrant.revoke(at: url, instanceID: mcpInstanceID)
        }
        mcpGrantURL = nil
    }

    // MARK: - Private helpers

    private func traceStartup(_ phase: String, since startedAt: TimeInterval) {
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
        logger.info("[startup] \(phase, privacy: .public) elapsed_ms=\(milliseconds)")
    }

    private func generateAccessToken() -> String {
        var bytes = Data(count: 32)
        bytes.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        return bytes.base64EncodedString()
    }

    /// Kill stale codeagentd processes left over from a previous app
    /// launch or crash. These would hold old ports/tokens and interfere
    /// with the new daemon.
    ///
    /// Scoped to THIS bundle's daemon binary path: the previous
    /// `pkill -9 -f codeagentd` matched every process whose command line
    /// merely contained "codeagentd", so a second Talkify instance would
    /// SIGKILL the first instance's live daemon (and vice versa), triggering
    /// the crash-restart loop and risking concurrent writes to the shared
    /// sessions.db. With the single-instance guard in TalkifyApp, the only
    /// same-path daemons that can exist here are stale leftovers of this
    /// very app — killing them is safe and never touches another app's
    /// process (even one that happens to be named codeagentd).
    private func killExistingDaemons() async {
        guard let daemonURL else { return }
        await Self.runAndWait(executable: "/usr/bin/pkill", arguments: ["-9", "-f", daemonURL.path])
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Resolve the user's full login-shell environment. Unlike
    /// `ProcessInfo.processInfo.environment` (which inherits launchd's
    /// minimal set), this runs `zsh -l -c 'env'` to capture API keys,
    /// PATH, and everything else defined in `~/.zshrc` / `~/.zprofile`.
    ///
    /// A few noise entries (`_`, `PWD`, `SHLVL`, `ZSH*`) are stripped.
    private func resolveUserShellEnvironment() async -> [String: String] {
        let output = await Self.runAndCapture(
            executable: "/bin/zsh",
            arguments: ["-c", "source \"$HOME/.zprofile\" 2>/dev/null; source \"$HOME/.zshrc\" 2>/dev/null; env"],
            environment: ["HOME": NSHomeDirectory()]
        )
        // Explicitly source the user's shell config files to pick up API keys
        // (DEEPSEEK_API_KEY, etc.) defined there, then dump the environment.
        // -l alone sources ~/.zprofile but NOT ~/.zshrc (needs -i, which
        // requires a TTY), so we source both explicitly. Errors are ignored
        // so the command succeeds even if a file is missing.
        var env: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            if key == "_" || key == "PWD" || key == "SHLVL" || key.hasPrefix("ZSH") { continue }
            env[key] = String(parts[1])
        }

        // Fallback: at least ensure a usable PATH.
        if env["PATH"]?.isEmpty ?? true {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        return env
    }

    private nonisolated static func runAndWait(executable: String, arguments: [String]) async {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.terminationHandler = { _ in continuation.resume() }
            do { try task.run() } catch { continuation.resume() }
        }
    }

    private nonisolated static func runAndCapture(
        executable: String, arguments: [String], environment: [String: String]
    ) async -> String {
        await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.environment = environment
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                // Shell profiles may call slow external tools. Bound this phase,
                // and drain stdout while the shell is running to avoid pipe stalls.
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5)) {
                    guard task.isRunning else { return }
                    task.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                        if task.isRunning { _ = Darwin.kill(task.processIdentifier, SIGKILL) }
                    }
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        }.value
    }

    /// Resolve the user's full shell PATH by sourcing a login shell.
    ///
    /// macOS GUI apps launched from Finder/Dock inherit a minimal PATH
    /// (`/usr/bin:/bin`). Running `zsh -l -c 'echo -n $PATH'` sources
    /// `~/.zshrc`, `~/.zprofile`, etc. so tools installed via Homebrew,
    /// Go, Node, Python, and other user-level package managers are discovered.
    private func resolveUserShellPATH() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "echo -n $PATH"]
        task.environment = ["HOME": NSHomeDirectory()]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty {
                return path
            }
        } catch {
            logger.warning("Failed to resolve user shell PATH: \(error.localizedDescription)")
        }

        // Fallback: common tool locations
        return [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/go/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
    }

    /// Read the port-file written by `codeagentd --port-file`. The file
    /// contains a single integer — the actual TCP port the daemon is
    /// listening on. Poll until the file appears or timeout.
    private func waitForPortFile(at url: URL, timeout: TimeInterval) async throws -> Int {
        let startedAt = ProcessInfo.processInfo.systemUptime
        var allowedWait = timeout
        while ProcessInfo.processInfo.systemUptime - startedAt < allowedWait {
            try Task.checkCancellation()
            if requiresIndexMigration, allowedWait == timeout {
                // One-time schema work must not be killed/restarted at the normal
                // startup deadline. Subsequent opens skip this work entirely.
                allowedWait = timeout * 3
                logger.info("[startup] first-time index migration; deadline_seconds=\(Int(allowedWait))")
            }
            if let data = try? Data(contentsOf: url),
               let content = String(data: data, encoding: .utf8)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               let port = Int(content), port > 0 {
                return port
            }
            // Check if the process died before writing the port-file
            if let process, !process.isRunning {
                throw CodeAgentDaemonError.launchFailed(
                    "Process exited with status \(process.terminationStatus) before port-file was written."
                )
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CodeAgentDaemonError.startupTimedOut(seconds: allowedWait, progress: startupProgress)
    }

    /// Called when the daemon process terminates. If it crashed (uncaught
    /// signal), attempt a one-shot restart.
    private func handleTermination(pid: Int32, status: Int32, reason: Process.TerminationReason) {
        guard process?.processIdentifier == pid else { return }
        try? revokeMCPConnection()
        logger.info("codeagentd terminated (status: \(status), reason: \(String(describing: reason)))")
        process = nil
        port = 0

        if let url = portFileURL {
            try? FileManager.default.removeItem(at: url)
            portFileURL = nil
        }

        if reason == .uncaughtSignal && status != 0 {
            logger.warning("codeagentd crashed — attempting restart")
            Task { @MainActor [weak self] in
                if let restart = self?.onRestartNeeded {
                    await restart()
                    return
                }
                do {
                    try await self?.start()
                } catch {
                    self?.logger.error("codeagentd restart failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// URLSessionDelegate that accepts self-signed TLS certificates on loopback.
/// The daemon may enable TLS from ~/.codeagent/settings.json with a self-signed
/// cert. On 127.0.0.1 this is safe — no network exposure.
private final class LoopbackTLSAcceptingDelegate: NSObject, URLSessionDelegate {
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
#endif
