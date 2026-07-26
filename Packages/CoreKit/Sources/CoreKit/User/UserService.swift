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

    public func deleteAccount() async throws -> DeleteAccountResponse {
        try await apiProvider.request(endpoint: UserApi.deleteAccount)
    }
}

/// 删除账号接口的成功响应。服务端当前不要求客户端读取具体字段。
public struct DeleteAccountResponse: Codable, Sendable {}
