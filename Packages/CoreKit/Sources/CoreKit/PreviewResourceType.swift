import Foundation

public enum PreviewResourceType: String, Codable, Sendable, Hashable, CaseIterable {
    case video
    case image
    case audio
    case timeline
    case unknown

    public init(rawValueSafe rawValue: String?) {
        guard let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            let value = PreviewResourceType(rawValue: normalized) else {
            self = .unknown
            return
        }

        self = value
    }

    public var isVideo: Bool { self == .video }
    public var isImage: Bool { self == .image }
    public var isAudio: Bool { self == .audio }
    public var isTimeline: Bool { self == .timeline }

    public var displayTitle: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .audio: return "音频"
        case .timeline: return "时间线剪辑"
        case .unknown: return "未知"
        }
    }

    public var systemImageName: String {
        switch self {
        case .video: return "video"
        case .image: return "photo"
        case .audio: return "waveform"
        case .timeline: return "scissors"
        case .unknown: return "square.slash"
        }
    }
}
