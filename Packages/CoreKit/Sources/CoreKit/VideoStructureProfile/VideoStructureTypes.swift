//
//  VideoStructureTypes.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/6/11.
//

import Foundation
import CoreGraphics

public enum VideoEvidenceReviewFrameStatus: String, Codable, Sendable {
    case pending
    case recognized
    case failed
}

/// 生成前证据审阅工作台使用的单条 OCR 原始证据。
///
/// 该模型保持不可变，不包含用户勾选/删除等 UI 编辑态。
public struct VideoEvidenceReviewOCRObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    /// 原始视频像素坐标 `[x1, y1, x2, y2]`
    public let bbox: [Double]
    public let confidence: Float

    public init(
        id: String,
        text: String,
        bbox: [Double],
        confidence: Float
    ) {
        self.id = id
        self.text = text
        self.bbox = bbox
        self.confidence = confidence
    }
}

/// 生成前证据审阅工作台使用的全采样帧数据。
///
/// CoreKit 只输出原始证据：缩略图、时间点、视频尺寸和 OCR 候选。
/// 是否保留、删除、重置由 Feature 层的 EvidenceReview UI State 管理。
public struct VideoEvidenceReviewFrame: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let keyframeID: String
    public let time: Double
    public let thumbnailData: Data
    public let videoSize: CGSize
    public let status: VideoEvidenceReviewFrameStatus
    public let observations: [VideoEvidenceReviewOCRObservation]

    public init(
        id: String,
        keyframeID: String,
        time: Double,
        thumbnailData: Data,
        videoSize: CGSize,
        status: VideoEvidenceReviewFrameStatus,
        observations: [VideoEvidenceReviewOCRObservation]
    ) {
        self.id = id
        self.keyframeID = keyframeID
        self.time = time
        self.thumbnailData = thumbnailData
        self.videoSize = videoSize
        self.status = status
        self.observations = observations
    }
}

public enum VideoEvidenceReviewExtractionEvent: Sendable {
    case prepared([VideoEvidenceReviewFrame])
    case frameUpdated(VideoEvidenceReviewFrame)
}

/// 视频画面上识别到的单条文字。
///
/// 服务端协议字段，序列化时 `bbox` 使用像素坐标 `[x1, y1, x2, y2]`
/// 以便服务端无需知晓视频分辨率即可定位文字区域。
public struct VideoOCRItem: Codable, Sendable, Equatable {
    /// 去重后的文字段 ID，如 `"seg_001"`
    public let segmentID: String
    /// 来源关键帧 ID，如 `"kf_003"`
    public let keyframeID: String
    /// 视频时间戳（秒）
    public let time: Double
    /// 识别到的文字内容
    public let text: String
    /// 像素坐标 `[x1, y1, x2, y2]`
    public let bbox: [Double]
    /// Vision 识别置信度 0...1
    public let confidence: Float
    /// 固定 `"ios_vision"`
    public let source: String

    public init(
        segmentID: String,
        keyframeID: String,
        time: Double,
        text: String,
        bbox: [Double],
        confidence: Float,
        source: String = "ios_vision"
    ) {
        self.segmentID = segmentID
        self.keyframeID = keyframeID
        self.time = time
        self.text = text
        self.bbox = bbox
        self.confidence = confidence
        self.source = source
    }
}

/// 视频语音转录的单个片段。
///
/// 对应 `SFSpeechRecognitionResult` 的 segment 级别的结果。
public struct VideoTranscriptSegment: Codable, Sendable, Equatable {
    /// 片段起始时间（秒）
    public let start: Double
    /// 片段结束时间（秒）
    public let end: Double
    /// 转录文本
    public let text: String
    /// 说话人标识（当前版本为空，预留）
    public let speaker: String
    /// 识别置信度 0...1
    public let confidence: Float
    /// 固定 `"ios_speech"`
    public let source: String

    public init(
        start: Double,
        end: Double,
        text: String,
        speaker: String = "",
        confidence: Float,
        source: String = "ios_speech"
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.confidence = confidence
        self.source = source
    }
}

/// 客户端本地提取的视频结构化信息。
///
/// 传给服务端 `video_to_prompt` 任务的 `video_structure` 字段。
/// 服务端收到非空结果时优先使用，空则 fallback 到 dream-ai-tools。
public struct VideoStructure: Codable, Sendable, Equatable {
    public let ocrItems: [VideoOCRItem]
    public let transcript: [VideoTranscriptSegment]
    /// 固定 `"ios"`
    public let source: String
    /// 协议版本，当前 `"v1"`
    public let version: String

    public init(
        ocrItems: [VideoOCRItem],
        transcript: [VideoTranscriptSegment],
        source: String = "ios",
        version: String = "v1"
    ) {
        self.ocrItems = ocrItems
        self.transcript = transcript
        self.source = source
        self.version = version
    }

    /// 两端都为空时返回 `nil`，避免上传无意义的空结构。
    public var orNil: VideoStructure? {
        if ocrItems.isEmpty && transcript.isEmpty { return nil }
        return self
    }
}
