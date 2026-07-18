import Foundation

public enum UserApi: ApiEndpoint {
    case profile
    case updateProfile(nickname: String?, avatarURL: String?)
    
    public var path: String {
        switch self {
        case .profile:
            return "user/profile"
        case .updateProfile:
            return "user/profile"
        }
    }
    
    public var method: HTTPMethod {
        switch self {
        case .profile:
            return .get
        case .updateProfile:
            return .patch
        }
    }
    
    public var parameters: [String : Sendable] {
        switch self {
        case .profile:
            return [:]
        case .updateProfile(let nickname, let avatarURL):
            var parameters: [String: Sendable] = [:]
            if let nickname {
                parameters["nickname"] = nickname
            }
            if let avatarURL {
                parameters["avatar_url"] = avatarURL
            }
            return parameters
        }
    }
}
