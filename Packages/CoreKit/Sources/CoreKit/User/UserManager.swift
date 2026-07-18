import Foundation
import Observation

@Observable
@MainActor
public final class UserManager {
    public private(set) var profile: UserProfile?
    public private(set) var isLoading = false
    public private(set) var lastUpdatedAt: Date?
    public var lastErrorMessage: String?
    
    public var isLoaded: Bool { profile != nil }
    
    private let service: UserService
    private let store = UserDefaults.standard
    private var environment: AppEnvironment
    private let cacheKeyPrefix = "com.objc.dreamlog.userProfile"
    
    public init(service: UserService, environment: AppEnvironment = .prod) {
        self.service = service
        self.environment = environment
        loadCachedProfile()
    }
    
    public func fetchProfile() async throws -> UserProfile {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let profile = try await service.fetchProfile()
            updateProfile(profile)
            lastErrorMessage = nil
            return profile
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    public func refreshProfileIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastUpdatedAt, Date().timeIntervalSince(lastUpdatedAt) < maxAge, profile != nil {
            return
        }
        
        _ = try? await fetchProfile()
    }

    @discardableResult
    public func updateProfile(nickname: String?, avatarURL: String?) async throws -> UserProfile {
        isLoading = true
        defer { isLoading = false }

        do {
            let profile = try await service.updateProfile(nickname: nickname, avatarURL: avatarURL)
            updateProfile(profile)
            lastErrorMessage = nil
            return profile
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    public func updateProfile(_ profile: UserProfile?) {
        self.profile = profile
        lastUpdatedAt = profile == nil ? nil : Date()
        
        guard let profile else {
            store.removeObject(forKey: cacheKey)
            return
        }
        
        if let data = try? JSONEncoder().encode(profile) {
            store.set(data, forKey: cacheKey)
        }
    }
    
    public func clear() {
        updateProfile(nil)
        lastErrorMessage = nil
        isLoading = false
    }

    public func switchEnvironment(_ environment: AppEnvironment) {
        self.environment = environment
        profile = nil
        lastUpdatedAt = nil
        lastErrorMessage = nil
        isLoading = false
        loadCachedProfile()
    }
    
    private func loadCachedProfile() {
        guard let data = store.data(forKey: cacheKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return
        }
        self.profile = profile
    }

    private var cacheKey: String {
        "\(cacheKeyPrefix).\(environment.rawValue)"
    }
}
