//
//  VideoStructureProfiler.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/6/11.
//

import Foundation
import AVFoundation
import Vision
import Speech
import ImageIO
import UniformTypeIdentifiers

// MARK: - Error

enum VideoStructureError: Error, LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case audioExtractionFailed
    case speechRecognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:      return "视频没有画面轨道"
        case .noAudioTrack:      return "视频没有音频轨道"
        case .audioExtractionFailed: return "音频提取失败"
        case .speechRecognizerUnavailable: return "语音识别不可用"
        }
    }
}

// MARK: - Profiler

/// 客户端本地视频结构化信息提取器。
///
/// 从视频中并行提取两类信息：
/// 1. **OCR**：按间隔抽关键帧，用 Apple Vision (`VNRecognizeTextRequest`) 识别画面文字
/// 2. **ASR**：提取音频轨道，用 Apple Speech (`SFSpeechRecognizer`) 转录音频
///
/// 设计原则：
/// - OCR / ASR 各自容错，一端失败不影响另一端
/// - 不支持 ASR 的 locale 或用户未授权时，transcript 返回空
/// - 结果可通过 `VideoStructureStore` 缓存复用
///
/// 使用示例：
/// ```swift
/// let structure = try? await VideoStructureProfiler.shared.extractStructure(
///     from: videoURL,
///     fpsSampling: 0.5   // 每 2 秒抽 1 帧做 OCR
/// )
/// ```
public final class VideoStructureProfiler: Sendable {

    public static let shared = VideoStructureProfiler()
    private init() {}

    // MARK: - Public API

    /// 提取视频结构化信息（OCR + ASR 并行）。
    ///
    /// - Parameters:
    ///   - videoURL: 本地沙盒视频 URL
    ///   - fpsSampling: OCR 关键帧采样率（帧/秒），默认 0.5（每 2 秒 1 帧）
    ///   - speechLocale: ASR 语言，默认 `zh-CN`；为 nil 时使用设备当前 locale
    /// - Returns: `VideoStructure`，两端都为空时 `orNil` 返回 nil
    public func extractStructure(
        from videoURL: URL,
        fpsSampling: Double = 0.5,
        speechLocale: Locale? = Locale(identifier: "zh-CN")
    ) async throws -> VideoStructure {
        var localURL = videoURL
        if !videoURL.isFileURL {
            localURL = try await VideoCacheManager.shared.downloadVideo(url: videoURL)
        }
        let asset = AVURLAsset(url: localURL)

        // 用独立 Task 替代 async let：
        // async let 在隐式 task group 中，任意一个 throw 会取消另一个；
        // 独立 Task 之间完全解耦，各自的错误只影响自己。
        let ocrTask = Task<[VideoOCRItem], Never> {
            do {
                return try await extractOCR(from: asset, fpsSampling: fpsSampling)
            } catch {
                #if DEBUG
                print("[VideoStructureProfiler] OCR 提取失败: \(error)")
                #endif
                return []
            }
        }
        let asrTask = Task<[VideoTranscriptSegment], Never> {
            do {
                return try await extractTranscript(from: asset, locale: speechLocale)
            } catch {
                #if DEBUG
                print("[VideoStructureProfiler] ASR 提取失败: \(error)")
                #endif
                return []
            }
        }

        let ocr = await ocrTask.value
        let asr = await asrTask.value

        return VideoStructure(ocrItems: ocr, transcript: asr)
    }

    /// 提取生成前证据审阅工作台所需的全采样 OCR 帧。
    ///
    /// 与 `extractStructure` 不同，该接口不会去重，也不会隐藏无文字帧或失败帧；
    /// UI 可通过 `onEvent` 先拿到所有待分析帧，再逐帧更新 OCR 结果。
    public func extractEvidenceReviewFrames(
        from videoURL: URL,
        fpsSampling: Double = 1.0,
        onEvent: (@Sendable (VideoEvidenceReviewExtractionEvent) -> Void)? = nil
    ) async throws -> [VideoEvidenceReviewFrame] {
        var localURL = videoURL
        if !videoURL.isFileURL {
            localURL = try await VideoCacheManager.shared.downloadVideo(url: videoURL)
        }
        let asset = AVURLAsset(url: localURL)
        let (frameImages, videoSize) = try await extractKeyframes(
            from: asset,
            fpsSampling: fpsSampling
        )
        guard !frameImages.isEmpty else { return [] }

        var frames = frameImages.enumerated().map { index, frame in
            makeEvidenceReviewFrame(
                index: index,
                frame: frame,
                videoSize: videoSize,
                status: .pending,
                observations: []
            )
        }
        onEvent?(.prepared(frames))

        for (index, frame) in frameImages.enumerated() {
            let updated: VideoEvidenceReviewFrame
            do {
                let observations = try recognizeEvidenceReviewOCR(
                    in: frame,
                    frameIndex: index,
                    videoSize: videoSize
                )
                updated = makeEvidenceReviewFrame(
                    index: index,
                    frame: frame,
                    videoSize: videoSize,
                    status: .recognized,
                    observations: observations
                )
            } catch {
                #if DEBUG
                print("[VideoStructureProfiler] EvidenceReview OCR frame \(index + 1) failed: \(error)")
                #endif
                updated = makeEvidenceReviewFrame(
                    index: index,
                    frame: frame,
                    videoSize: videoSize,
                    status: .failed,
                    observations: []
                )
            }

            frames[index] = updated
            onEvent?(.frameUpdated(updated))
        }

        return frames
    }

    /// 按指定时间点提取单个 EvidenceReview OCR 帧。
    ///
    /// 用于时间轴相邻帧之间的局部补帧，不影响全局采样策略。
    public func extractEvidenceReviewFrame(
        from videoURL: URL,
        at time: Double,
        keyframeID: String? = nil
    ) async throws -> VideoEvidenceReviewFrame {
        var localURL = videoURL
        if !videoURL.isFileURL {
            localURL = try await VideoCacheManager.shared.downloadVideo(url: videoURL)
        }
        let asset = AVURLAsset(url: localURL)
        let videoSize = try await loadVideoSize(from: asset)
        let frame = try await extractKeyframe(from: asset, at: time)
        let id = keyframeID ?? String(format: "manual_kf_%.3f", frame.time)

        do {
            let observations = try recognizeEvidenceReviewOCR(
                in: frame,
                keyframeID: id,
                videoSize: videoSize
            )
            return makeEvidenceReviewFrame(
                keyframeID: id,
                frame: frame,
                videoSize: videoSize,
                status: .recognized,
                observations: observations
            )
        } catch {
            #if DEBUG
            print("[VideoStructureProfiler] EvidenceReview OCR single frame \(id) failed: \(error)")
            #endif
            return makeEvidenceReviewFrame(
                keyframeID: id,
                frame: frame,
                videoSize: videoSize,
                status: .failed,
                observations: []
            )
        }
    }

    /// 提取生成前证据审阅工作台所需的 ASR 原始片段。
    ///
    /// CoreKit 只输出原始识别结果；编辑、删除、降噪筛选由 Feature 层维护。
    public func extractEvidenceReviewTranscript(
        from videoURL: URL,
        speechLocale: Locale? = Locale(identifier: "zh-CN")
    ) async throws -> [VideoTranscriptSegment] {
        var localURL = videoURL
        if !videoURL.isFileURL {
            localURL = try await VideoCacheManager.shared.downloadVideo(url: videoURL)
        }
        let asset = AVURLAsset(url: localURL)
        return try await extractTranscript(from: asset, locale: speechLocale)
    }

    // MARK: - OCR Extraction

    private func extractOCR(
        from asset: AVAsset,
        fpsSampling: Double
    ) async throws -> [VideoOCRItem] {
        let (frameImages, videoSize) = try await extractKeyframes(
            from: asset,
            fpsSampling: fpsSampling
        )
        guard !frameImages.isEmpty else { return [] }

        let frameObservations = try await recognizeText(
            in: frameImages,
            videoSize: videoSize
        )

        return deduplicateOCRItems(frameObservations)
    }

    // MARK: - ASR Extraction

    private func extractTranscript(
        from asset: AVAsset,
        locale: Locale?
    ) async throws -> [VideoTranscriptSegment] {
        // 检查是否有音频轨道
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return [] }

        // 提取 PCM 数据 + WAV 文件
        let (wavURL, pcmData) = try await extractAudioTrack(from: asset)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        // 能量检测找语音段 (解决 iOS 18 停顿丢弃文本的 Bug)
        let segments = detectSpeechSegments(pcmData: pcmData, sampleRate: 44100)
        guard !segments.isEmpty else { return [] }

        #if DEBUG
        print("[VideoStructureProfiler] VAD 检测到 \(segments.count) 个语音段: "
              + segments.map { "\(String(format: "%.1f", $0.start))s–\(String(format: "%.1f", $0.end))s" }.joined(separator: ", "))
        #endif

        // 逐段识别
        var allSegments: [VideoTranscriptSegment] = []
        for seg in segments {
            let segWAV = try writeSpeechSegmentWAV(
                pcmData: pcmData,
                sampleRate: 44100,
                segment: seg
            )
            defer { try? FileManager.default.removeItem(at: segWAV) }

            do {
                let transcript = try await transcribeAudio(at: segWAV, locale: locale)
                let speechStart = seg.start  // 该语音段在完整音频中的偏移
                let offsetSegments = transcript.map { ts in
                    VideoTranscriptSegment(
                        start: ts.start + speechStart,
                        end: ts.end + speechStart,
                        text: ts.text,
                        speaker: ts.speaker,
                        confidence: ts.confidence,
                        source: ts.source
                    )
                }
                allSegments.append(contentsOf: offsetSegments)
            } catch {
                #if DEBUG
                print("[VideoStructureProfiler] ASR 段 \(String(format: "%.1f", seg.start))s–\(String(format: "%.1f", seg.end))s 识别失败: \(error)")
                #endif
            }
        }

        return Self.mergeTranscriptSegments(allSegments)
    }

    /// 语音段描述
    struct SpeechSegment {
        let start: Double  // 秒
        let end: Double
    }

    /// 基于 RMS 能量的简单 VAD。
    ///
    /// 窗口 100ms，能量超过自适应阈值视为语音，
    /// 相邻语音窗口间隔较短时合并为适合 Speech 识别的语音块。
    func detectSpeechSegments(pcmData: Data, sampleRate: Int) -> [SpeechSegment] {
        let windowSize = sampleRate / 10  // 100ms
        let sampleCount = pcmData.count / 2  // 16-bit
        guard sampleCount > windowSize else { return [] }

        // 计算每窗口 RMS
        var rmsValues: [Double] = []
        let rawPtr = pcmData.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
        var offset = 0
        while offset + windowSize <= sampleCount {
            var sumSq: Double = 0
            for i in 0..<windowSize {
                let sample = Double(rawPtr[offset + i]) / Double(Int16.max)
                sumSq += sample * sample
            }
            rmsValues.append(sqrt(sumSq / Double(windowSize)))
            offset += windowSize
        }

        guard !rmsValues.isEmpty else { return [] }

        // 自适应阈值：结合低分位噪声底和平均能量，避免背景声较高时把人声切碎。
        let meanRMS = rmsValues.reduce(0, +) / Double(rmsValues.count)
        let sortedRMS = rmsValues.sorted()
        let noiseFloor = sortedRMS[max(0, min(sortedRMS.count - 1, Int(Double(sortedRMS.count) * 0.2)))]
        let threshold = max(noiseFloor * 2.2, meanRMS * 0.65, 0.012)

        // 窗口 → 语音/静音标记
        let isSpeech = rmsValues.map { $0 > threshold }

        // 合并相邻语音窗口
        let windowDuration = Double(windowSize) / Double(sampleRate)
        let maxMergeGap = 1.2  // 秒
        let maxGapWindows = Int(maxMergeGap / windowDuration)

        var segments: [SpeechSegment] = []
        var i = 0
        while i < isSpeech.count {
            guard isSpeech[i] else { i += 1; continue }

            var j = i
            var gapCount = 0
            while j < isSpeech.count {
                if isSpeech[j] {
                    gapCount = 0
                    j += 1
                } else if gapCount < maxGapWindows {
                    gapCount += 1
                    j += 1
                } else {
                    break
                }
            }

            let start = Double(i) * windowDuration
            let end = Double(j - gapCount) * windowDuration

            if end - start >= 0.2 {
                segments.append(SpeechSegment(start: start, end: end))
            }

            i = j
        }

        return normalizeSpeechSegments(
            segments,
            audioDuration: Double(sampleCount) / Double(sampleRate)
        )
    }

    func normalizeSpeechSegments(
        _ segments: [SpeechSegment],
        audioDuration: Double
    ) -> [SpeechSegment] {
        guard !segments.isEmpty else { return [] }

        let prePadding = 0.35
        let postPadding = 0.45
        let maxMergeGap = 1.2
        let minDuration = 0.8
        let maxDuration = 14.0

        let padded = segments.map { segment in
            SpeechSegment(
                start: max(0, segment.start - prePadding),
                end: min(audioDuration, segment.end + postPadding)
            )
        }

        var merged: [SpeechSegment] = []
        for segment in padded {
            guard var last = merged.popLast() else {
                merged.append(segment)
                continue
            }

            let gap = segment.start - last.end
            if gap <= maxMergeGap || last.end - last.start < minDuration {
                last = SpeechSegment(start: last.start, end: max(last.end, segment.end))
                merged.append(last)
            } else {
                merged.append(last)
                merged.append(segment)
            }
        }

        var normalized: [SpeechSegment] = []
        for segment in merged where segment.end > segment.start {
            if segment.end - segment.start <= maxDuration {
                normalized.append(segment)
                continue
            }

            var start = segment.start
            while start < segment.end {
                let end = min(segment.end, start + maxDuration)
                normalized.append(SpeechSegment(start: start, end: end))
                start = end
            }
        }

        return normalized.filter { $0.end - $0.start >= minDuration }
    }

    /// 从完整 PCM 数据中截取一段，写出独立 WAV 文件
    func writeSpeechSegmentWAV(pcmData: Data, sampleRate: Int, segment: SpeechSegment) throws -> URL {
        let bytesPerSample = 2
        let sampleRateD = Double(sampleRate)
        let startByte = Int(segment.start * sampleRateD) * bytesPerSample
        let endByte   = Int(segment.end   * sampleRateD) * bytesPerSample
        let clampedStart = max(0, min(startByte, pcmData.count))
        let clampedEnd   = max(clampedStart, min(endByte, pcmData.count))
        let segData = pcmData.subdata(in: clampedStart..<clampedEnd)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try writeWAV(data: segData, sampleRate: sampleRate, to: url)
        return url
    }
}

// MARK: - Keyframe Extraction

private extension VideoStructureProfiler {

    /// 视频关键帧数据：CGImage + 时间戳
    struct FrameImage {
        let cgImage: CGImage
        let time: Double
    }

    /// 从视频中按固定间隔抽取关键帧。
    ///
    /// - Returns: 帧数组（按时间排序）和视频像素尺寸
    func extractKeyframes(
        from asset: AVAsset,
        fpsSampling: Double
    ) async throws -> ([FrameImage], CGSize) {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return ([], .zero)
        }

        let videoSize = try await loadVideoSize(from: asset)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        let frameInterval = 1.0 / max(0.1, fpsSampling)
        var times: [CMTime] = []
        var t = 0.0
        while t < durationSeconds {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += frameInterval
        }

        // 批量生成关键帧
        var frameImages: [FrameImage] = []
        frameImages.reserveCapacity(times.count)

        // 使用 CMSampleBuffer 风格的 result 回调批量获取
        // 注：generator.image(at:) async 版本内部也是串行，
        // 这里按时间顺序逐个获取保证稳定性。
        for time in times {
            do {
                let (cgImage, actualTime) = try await generator.image(at: time)
                let seconds = CMTimeGetSeconds(actualTime)
                guard seconds.isFinite else { continue }
                frameImages.append(FrameImage(cgImage: cgImage, time: seconds))
            } catch {
                // 个别帧失败不阻塞整体流程
                #if DEBUG
                print("[VideoStructureProfiler] keyframe at \(CMTimeGetSeconds(time))s failed: \(error)")
                #endif
                continue
            }
        }

        return (frameImages, videoSize)
    }

    func loadVideoSize(from asset: AVAsset) async throws -> CGSize {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoStructureError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        return CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )
    }

    func extractKeyframe(
        from asset: AVAsset,
        at seconds: Double
    ) async throws -> FrameImage {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let clampedTime = max(0, min(seconds, durationSeconds.isFinite ? durationSeconds : seconds))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let time = CMTime(seconds: clampedTime, preferredTimescale: 600)
        let (cgImage, actualTime) = try await generator.image(at: time)
        let actualSeconds = CMTimeGetSeconds(actualTime)
        return FrameImage(
            cgImage: cgImage,
            time: actualSeconds.isFinite ? actualSeconds : clampedTime
        )
    }
}

// MARK: - Vision OCR

private extension VideoStructureProfiler {

    /// 单帧 OCR 原始结果
    struct FrameOCRResult {
        let keyframeID: String
        let time: Double
        let observations: [RawOCRObservation]
    }

    struct RawOCRObservation {
        let text: String
        let bbox: [Double]   // 像素坐标 [x1, y1, x2, y2]
        let confidence: Float
    }

    /// 对所有关键帧运行 Vision OCR 文字识别。
    func recognizeText(
        in frames: [FrameImage],
        videoSize: CGSize
    ) async throws -> [FrameOCRResult] {
        var results: [FrameOCRResult] = []
        results.reserveCapacity(frames.count)

        for (index, frame) in frames.enumerated() {
            let keyframeID = String(format: "kf_%03d", index + 1)

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: frame.cgImage, options: [:])
            do {
                try handler.perform([request])

                let observations = (request.results ?? []).compactMap { $0 as? VNRecognizedTextObservation }
                guard !observations.isEmpty else { continue }

                let rawObs: [RawOCRObservation] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }

                    let bbox = convertBoundingBox(
                        observation.boundingBox,
                        videoSize: videoSize
                    )
                    return RawOCRObservation(
                        text: text,
                        bbox: bbox,
                        confidence: candidate.confidence
                    )
                }

                if !rawObs.isEmpty {
                    results.append(FrameOCRResult(
                        keyframeID: keyframeID,
                        time: frame.time,
                        observations: rawObs
                    ))
                }
            } catch {
                #if DEBUG
                print("[VideoStructureProfiler] OCR frame \(keyframeID) failed: \(error)")
                #endif
                continue
            }
        }

        return results
    }

    func recognizeEvidenceReviewOCR(
        in frame: FrameImage,
        frameIndex: Int,
        videoSize: CGSize
    ) throws -> [VideoEvidenceReviewOCRObservation] {
        let keyframeID = String(format: "kf_%03d", frameIndex + 1)
        return try recognizeEvidenceReviewOCR(
            in: frame,
            keyframeID: keyframeID,
            videoSize: videoSize
        )
    }

    func recognizeEvidenceReviewOCR(
        in frame: FrameImage,
        keyframeID: String,
        videoSize: CGSize
    ) throws -> [VideoEvidenceReviewOCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: frame.cgImage, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? []).compactMap { $0 as? VNRecognizedTextObservation }
        return observations.enumerated().compactMap { observationIndex, observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let bbox = convertBoundingBox(
                observation.boundingBox,
                videoSize: videoSize
            )
            return VideoEvidenceReviewOCRObservation(
                id: "\(keyframeID)_obs_\(String(format: "%03d", observationIndex + 1))",
                text: text,
                bbox: bbox,
                confidence: candidate.confidence
            )
        }
    }

    func makeEvidenceReviewFrame(
        index: Int,
        frame: FrameImage,
        videoSize: CGSize,
        status: VideoEvidenceReviewFrameStatus,
        observations: [VideoEvidenceReviewOCRObservation]
    ) -> VideoEvidenceReviewFrame {
        let keyframeID = String(format: "kf_%03d", index + 1)
        return makeEvidenceReviewFrame(
            keyframeID: keyframeID,
            frame: frame,
            videoSize: videoSize,
            status: status,
            observations: observations
        )
    }

    func makeEvidenceReviewFrame(
        keyframeID: String,
        frame: FrameImage,
        videoSize: CGSize,
        status: VideoEvidenceReviewFrameStatus,
        observations: [VideoEvidenceReviewOCRObservation]
    ) -> VideoEvidenceReviewFrame {
        return VideoEvidenceReviewFrame(
            id: keyframeID,
            keyframeID: keyframeID,
            time: frame.time,
            thumbnailData: jpegData(from: frame.cgImage, compressionQuality: 0.72) ?? Data(),
            videoSize: videoSize,
            status: status,
            observations: observations
        )
    }

    func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Vision 归一化坐标 (bottom-left origin, [0,1]) → 像素坐标 [x1, y1, x2, y2] (top-left origin)
    func convertBoundingBox(_ normalized: CGRect, videoSize: CGSize) -> [Double] {
        let x1 = normalized.origin.x * videoSize.width
        let y1 = (1.0 - normalized.origin.y - normalized.height) * videoSize.height
        let x2 = x1 + normalized.width * videoSize.width
        let y2 = y1 + normalized.height * videoSize.height
        return [Double(x1), Double(y1), Double(x2), Double(y2)]
    }
}

// MARK: - OCR Deduplication

private extension VideoStructureProfiler {

    /// 相邻帧去重：相同文字在连续关键帧中出现视为同一段。
    ///
    /// 策略：
    /// - 完全相同文字 → 同一 segment，保留首次出现时间和最高置信度
    /// - 字符级 Jaccard 相似度 > 0.7 → 也视为同一段（处理微小变化）
    func deduplicateOCRItems(_ frameResults: [FrameOCRResult]) -> [VideoOCRItem] {
        guard !frameResults.isEmpty else { return [] }

        var items: [VideoOCRItem] = []
        var segmentIndex = 0
        /// text → (items 中的下标, 当前最高置信度)
        var seen: [String: (index: Int, maxConfidence: Float)] = [:]

        for frame in frameResults {
            for obs in frame.observations {
                // 去重：先精确匹配，再模糊匹配
                let matchedKey = findMatch(for: obs.text, in: seen)

                if let key = matchedKey {
                    // 已存在：只更新更高的置信度
                    let entry = seen[key]!
                    if obs.confidence > entry.maxConfidence {
                        seen[key] = (entry.index, obs.confidence)
                        items[entry.index] = VideoOCRItem(
                            segmentID: items[entry.index].segmentID,
                            keyframeID: frame.keyframeID,
                            time: items[entry.index].time,
                            text: items[entry.index].text,
                            bbox: items[entry.index].bbox,
                            confidence: obs.confidence
                        )
                    }
                } else {
                    // 新 segment
                    segmentIndex += 1
                    let segmentID = String(format: "seg_%03d", segmentIndex)
                    let item = VideoOCRItem(
                        segmentID: segmentID,
                        keyframeID: frame.keyframeID,
                        time: frame.time,
                        text: obs.text,
                        bbox: obs.bbox,
                        confidence: obs.confidence
                    )
                    items.append(item)
                    seen[obs.text] = (items.count - 1, obs.confidence)
                }
            }
        }

        return items
    }

    /// 在已识别文字中查找匹配项。优先精确匹配，其次 Jaccard 相似度 > 0.7。
    private func findMatch(
        for text: String,
        in seen: [String: (index: Int, maxConfidence: Float)]
    ) -> String? {
        // 1. 精确匹配
        if seen[text] != nil { return text }

        // 2. 模糊匹配
        for key in seen.keys {
            if jaccardSimilarity(text, key) > 0.7 {
                return key
            }
        }

        return nil
    }

    /// 字符级 Jaccard 相似度：交集字符数 / 并集字符数
    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB)
        let union = setA.union(setB)
        return Double(intersection.count) / Double(union.count)
    }
}

// MARK: - Audio Extraction

private extension VideoStructureProfiler {

    /// 从视频中提取音频轨道到临时 WAV (PCM) 文件。
    ///
    /// 使用 `AVAssetReader` 读取原始 PCM 样本，再手动封装 WAV 头。
    /// PCM 格式对 `SFSpeechRecognizer` 比压缩格式（M4A/AAC）更稳定，
    /// 可避免编码器引入的静音填充或时长偏差导致的识别提前终止。
    func extractAudioTrack(from asset: AVAsset) async throws -> (wavURL: URL, pcmData: Data) {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoStructureError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(trackOutput) else { throw VideoStructureError.audioExtractionFailed }
        reader.add(trackOutput)
        guard reader.startReading() else { throw VideoStructureError.audioExtractionFailed }

        var sampleData = Data()
        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if let ptr = dataPointer, length > 0 {
                sampleData.append(UnsafeBufferPointer(start: ptr, count: length))
            }
        }

        guard reader.status == .completed, !sampleData.isEmpty else {
            throw VideoStructureError.audioExtractionFailed
        }

        // 写入 WAV 文件 (44 字节头 + 16-bit mono PCM)
        try writeWAV(data: sampleData, sampleRate: 44100, to: outputURL)

        #if DEBUG
        let videoDuration = try await asset.load(.duration)
        let audioSamples = Double(sampleData.count) / 2.0  // 16-bit = 2 bytes/sample
        let audioDuration = audioSamples / 44100.0
        print("[VideoStructureProfiler] 音频提取: 视频总长 \(CMTimeGetSeconds(videoDuration))s, "
              + "提取音频 \(String(format: "%.1f", audioDuration))s")
        #endif

        return (outputURL, sampleData)
    }

    /// 写入标准 WAV 文件头 + PCM 数据
    private func writeWAV(data: Data, sampleRate: Int, to url: URL) throws {
        let dataSize = UInt32(data.count)
        var header = Data()

        // RIFF header
        header.append("RIFF".data(using: .ascii)!)
        var chunkSize = UInt32(36 + dataSize).littleEndian
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        header.append("fmt ".data(using: .ascii)!)
        var subchunk1Size = UInt32(16).littleEndian
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian  // PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(1).littleEndian
        header.append(Data(bytes: &numChannels, count: 2))
        var sr = UInt32(sampleRate).littleEndian
        header.append(Data(bytes: &sr, count: 4))
        var byteRate = UInt32(sampleRate * 1 * 2).littleEndian
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        header.append(Data(bytes: &bitsPerSample, count: 2))

        // data subchunk
        header.append("data".data(using: .ascii)!)
        var subchunk2Size = dataSize.littleEndian
        header.append(Data(bytes: &subchunk2Size, count: 4))

        // 写入文件
        var output = header
        output.append(data)
        try output.write(to: url, options: .atomic)
    }
}

// MARK: - Speech Recognition

private extension VideoStructureProfiler {

    /// 使用 Apple Speech 框架转录音频。
    func transcribeAudio(
        at audioURL: URL,
        locale: Locale?
    ) async throws -> [VideoTranscriptSegment] {
        do {
            let localSegments = try await runSpeechRecognition(
                at: audioURL,
                locale: locale,
                requiresOnDeviceRecognition: true
            )
            if !localSegments.isEmpty {
                return localSegments
            }

            #if DEBUG
            print("[VideoStructureProfiler] ASR 本地识别返回空结果，尝试服务识别 fallback")
            #endif
        } catch {
            #if DEBUG
            print("[VideoStructureProfiler] ASR 本地识别失败，尝试服务识别 fallback: \(error)")
            #endif
        }

        return try await runSpeechRecognition(
            at: audioURL,
            locale: locale,
            requiresOnDeviceRecognition: false
        )
    }

    func runSpeechRecognition(
        at audioURL: URL,
        locale: Locale?,
        requiresOnDeviceRecognition: Bool
    ) async throws -> [VideoTranscriptSegment] {
        let speechLocale = locale ?? Locale.current

        guard let recognizer = SFSpeechRecognizer(locale: speechLocale),
              recognizer.isAvailable else {
            throw VideoStructureError.speechRecognizerUnavailable
        }

        // 检查授权状态
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .authorized:
            break
        case .denied, .restricted:
            return []
        case .notDetermined:
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else { return [] }
        @unknown default:
            return []
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, macOS 13.0, *) {
            request.addsPunctuation = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var latestResult: SFSpeechRecognitionResult?
            var fallbackWorkItem: DispatchWorkItem?
            var timeoutWorkItem: DispatchWorkItem?
            var recognitionTask: SFSpeechRecognitionTask?

            func transcriptSegments(from result: SFSpeechRecognitionResult) -> [VideoTranscriptSegment] {
                #if DEBUG
                let mode = requiresOnDeviceRecognition ? "on_device" : "server"
                let segmentCount = result.bestTranscription.segments.count
                let fullText = result.bestTranscription.formattedString
                let timeSpan: (Double, Double) = {
                    guard let first = result.bestTranscription.segments.first,
                          let last = result.bestTranscription.segments.last else {
                        return (0, 0)
                    }
                    return (first.timestamp, last.timestamp + last.duration)
                }()
                print("[VideoStructureProfiler] ASR 完成(\(mode)): "
                      + "\(segmentCount) raw segments, "
                      + "时间跨度 \(String(format: "%.1f", timeSpan.0))s–\(String(format: "%.1f", timeSpan.1))s, "
                      + "isFinal=\(result.isFinal), "
                      + "fullText: \"\(fullText.prefix(80))\""
                      + (fullText.count > 80 ? "…" : ""))
                #endif

                let rawSegments = result.bestTranscription.segments.map { segment in
                    VideoTranscriptSegment(
                        start: segment.timestamp,
                        end: segment.timestamp + segment.duration,
                        text: segment.substring.trimmingCharacters(in: .whitespacesAndNewlines),
                        speaker: "",
                        confidence: segment.confidence
                    )
                }

                return Self.mergeTranscriptSegments(rawSegments)
            }

            func finish(with result: SFSpeechRecognitionResult) {
                guard !hasResumed else { return }
                hasResumed = true
                fallbackWorkItem?.cancel()
                timeoutWorkItem?.cancel()
                recognitionTask?.cancel()
                continuation.resume(returning: transcriptSegments(from: result))
            }

            func finishEmpty() {
                guard !hasResumed else { return }
                hasResumed = true
                fallbackWorkItem?.cancel()
                timeoutWorkItem?.cancel()
                recognitionTask?.cancel()
                continuation.resume(returning: [])
            }

            func finish(throwing error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                fallbackWorkItem?.cancel()
                timeoutWorkItem?.cancel()
                recognitionTask?.cancel()
                continuation.resume(throwing: error)
            }

            func scheduleStableResultFallback() {
                fallbackWorkItem?.cancel()
                let workItem = DispatchWorkItem {
                    guard !hasResumed, let latestResult else { return }
                    finish(with: latestResult)
                }
                fallbackWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
            }

            let timeout = DispatchWorkItem {
                if let latestResult {
                    finish(with: latestResult)
                } else {
                    finishEmpty()
                }
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 24.0, execute: timeout)

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error {
                    if let latestResult {
                        finish(with: latestResult)
                    } else {
                        finish(throwing: error)
                    }
                    return
                }

                guard let result else {
                    // result 为 nil 且无 error → 仍在处理中，继续等待
                    return
                }

                let hasContent = !result.bestTranscription.formattedString.isEmpty
                guard hasContent else {
                    if result.isFinal {
                        finishEmpty()
                    }
                    return
                }

                latestResult = result
                if result.isFinal {
                    finish(with: result)
                } else {
                    scheduleStableResultFallback()
                }
            }
        }
    }

    /// 合并 Apple 中文 ASR 的字符级 segment 为句子级片段。
    ///
    /// 背景：`SFSpeechRecognizer` 对中文返回逐字 segment（"我"/"去"/"姥姥"/…），
    /// 而不是按词/句分组。同时低置信度片段通常是回声或误识别噪音。
    ///
    /// 策略：
    /// 1. 过滤 `confidence < 0.25` 的噪音片段
    /// 2. 过滤后出现 > 0.8s 的时间间隙视为句子边界
    /// 3. 同组内拼接文本，时间取首尾，置信度取平均
    static func mergeTranscriptSegments(_ segments: [VideoTranscriptSegment]) -> [VideoTranscriptSegment] {
        let minConfidence: Float = 0.25
        let maxMergeGap: Double = 0.8

        let filtered = segments.filter { $0.confidence >= minConfidence }
        guard !filtered.isEmpty else { return [] }

        var merged: [VideoTranscriptSegment] = []
        var current = filtered[0]

        for segment in filtered.dropFirst() {
            let gap = segment.start - current.end
            if gap < maxMergeGap {
                current = VideoTranscriptSegment(
                    start: current.start,
                    end: segment.end,
                    text: current.text + segment.text,
                    speaker: "",
                    confidence: (current.confidence + segment.confidence) / 2.0,
                    source: current.source
                )
            } else {
                merged.append(current)
                current = segment
            }
        }
        merged.append(current)

        return merged
    }
}
