import Foundation

enum CodeAgentDaemonError: Error, LocalizedError {
    case binaryNotFound
    case launchFailed(String)
    case notRunning
    case portNotResolved
    case startupTimedOut(seconds: TimeInterval, progress: String)
    case healthCheckTimeout

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "codeagentd binary not found in app bundle Resources."
        case .launchFailed(let detail):
            "Failed to launch codeagentd: \(detail)"
        case .notRunning:
            "codeagentd is not running."
        case .portNotResolved:
            "Could not determine codeagentd listening port."
        case .startupTimedOut(let seconds, let progress):
            "codeagentd did not publish its port within \(Int(seconds))s. Last startup phase: \(progress)"
        case .healthCheckTimeout:
            "codeagentd did not become ready within the timeout."
        }
    }
}
