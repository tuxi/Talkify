import Foundation
import Observation
/*
 │          用途          │                     推荐 URL                     │
 ├────────────────────────┼──────────────────────────────────────────────────┤
 │ App Store 隐私政策 URL │ https://objc.com/privacy?standalone=1            │
 ├────────────────────────┼──────────────────────────────────────────────────┤
 │ App Store 用户协议 URL │ https://objc.com/terms?standalone=1              │
 ├────────────────────────┼──────────────────────────────────────────────────┤
 │ 内容政策（合规公示）   │ https://objc.com/content-policy?standalone=1     │
 ├────────────────────────┼──────────────────────────────────────────────────┤
 │ 英文版隐私政策         │ https://objc.com/en/privacy?standalone=1         │
 ├────────────────────────┼──────────────────────────────────────────────────┤
 │ 英文版用户协议         │ https://objc.com/en/terms?standalone=1           │
 └────────────────────────┴────────────────────────────────────────────
 */

public struct AgreementURLs {
    /// 法律文档托管于 GitHub，确保链接始终可用。
    private static let legalBase = "https://github.com/tuxi/Talkify/blob/main/docs/legal"

    public static let privacy = URL(string: "\(legalBase)/privacy.md")!
    public static let terms = URL(string: "\(legalBase)/terms.md")!
    public static let content = URL(string: "\(legalBase)/content-policy.md")!
    public static let algorithmDisclosure = URL(string: "\(legalBase)/algorithm-disclosure.md")!
    public static let AIData = URL(string: "\(legalBase)/ai-data-processing.md")!
    public static let paid = URL(string: "\(legalBase)/pricing-terms.md")!
}

public enum AppEnvironment: String, CaseIterable, Codable, Sendable, Identifiable {
    case local
    case prod

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .prod:
            return "Prod"
        }
    }
}

public struct AppEnvironmentConfig: Codable, Sendable, Equatable {
    public let environment: AppEnvironment
    public let apiBaseURL: URL
    public let isPlaceholder: Bool

    public init(
        environment: AppEnvironment,
        apiBaseURL: URL,
        isPlaceholder: Bool = false,
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.isPlaceholder = isPlaceholder
    }
}

public struct EnvironmentRegistry: Sendable {
    private let configs: [AppEnvironment: AppEnvironmentConfig]
    public let defaultEnvironment: AppEnvironment

    public init(
        configs: [AppEnvironment: AppEnvironmentConfig],
        defaultEnvironment: AppEnvironment = .prod
    ) {
        self.configs = configs
        self.defaultEnvironment = defaultEnvironment
    }

    public func config(for environment: AppEnvironment) -> AppEnvironmentConfig {
        if let config = configs[environment] {
            return config
        }
        return configs[defaultEnvironment] ?? Self.live.config(for: .prod)
    }

    public var allConfigs: [AppEnvironmentConfig] {
        AppEnvironment.allCases.map { config(for: $0) }
    }
}

public extension EnvironmentRegistry {
    static let live: EnvironmentRegistry = {
        var configs: [AppEnvironment: AppEnvironmentConfig] = [
            .prod: AppEnvironmentConfig(
                environment: .prod,
                apiBaseURL: URL(string: "https://api.objc.com/api/v1")!,
            )
        ]
        #if DEBUG
        configs[.local] = AppEnvironmentConfig(
            environment: .local,
            apiBaseURL: URL(string: "http://192.168.1.10:12221/api/v1")!,
        )
        #endif
        return EnvironmentRegistry(configs: configs, defaultEnvironment: .prod)
    }()
}

@Observable
public final class EnvironmentManager: @unchecked Sendable {
    public private(set) var currentEnvironment: AppEnvironment

    private let registry: EnvironmentRegistry
    private let store: UserDefaults
    private let storeKey: String
    private let lock = NSLock()

    public init(
        registry: EnvironmentRegistry = .live,
        store: UserDefaults = .standard,
        storeKey: String = "com.objc.talkify.v2.currentEnvironment"
    ) {
        self.registry = registry
        self.store = store
        self.storeKey = storeKey

        #if DEBUG
        if let rawValue = store.string(forKey: storeKey),
           let environment = AppEnvironment(rawValue: rawValue) {
            self.currentEnvironment = environment
        } else {
            self.currentEnvironment = registry.defaultEnvironment
        }
        #else
        // Distribution builds must never inherit a persisted local/LAN environment.
        self.currentEnvironment = .prod
        #endif
    }

    public var currentEnvironmentSnapshot: AppEnvironment {
        lock.withLock { currentEnvironment }
    }

    public var currentConfig: AppEnvironmentConfig {
        registry.config(for: currentEnvironmentSnapshot)
    }

    public var availableConfigs: [AppEnvironmentConfig] {
        #if DEBUG
        registry.allConfigs
        #else
        [registry.config(for: .prod)]
        #endif
    }

    public func saveCurrentEnvironment(_ environment: AppEnvironment) {
        #if DEBUG
        let effectiveEnvironment = environment
        #else
        let effectiveEnvironment = AppEnvironment.prod
        #endif
        lock.withLock {
            currentEnvironment = effectiveEnvironment
            store.set(effectiveEnvironment.rawValue, forKey: storeKey)
        }
    }

    public func config(for environment: AppEnvironment) -> AppEnvironmentConfig {
        registry.config(for: environment)
    }
}
