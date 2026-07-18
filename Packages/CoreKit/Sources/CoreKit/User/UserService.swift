import Foundation

public final class UserService: @unchecked Sendable {
    private let apiProvider: ApiProvider
    
    public init(apiProvider: ApiProvider) {
        self.apiProvider = apiProvider
    }
    
    public func fetchProfile() async throws -> UserProfile {
        try await apiProvider.request(endpoint: UserApi.profile)
    }

    public func updateProfile(nickname: String?, avatarURL: String?) async throws -> UserProfile {
        try await apiProvider.request(endpoint: UserApi.updateProfile(nickname: nickname, avatarURL: avatarURL))
    }
}
