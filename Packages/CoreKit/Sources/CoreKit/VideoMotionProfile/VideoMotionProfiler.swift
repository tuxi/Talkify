//
//  VideoMotionProfiler.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/6/8.
//

import Foundation
import AVFoundation
import Accelerate
import CoreTransferable
import UniformTypeIdentifiers

/// One sampled point on a video's motion-energy curve.
///
/// Persisted (see `MotionProfileStore`) as a lightweight, read-only array.
/// V1.0 carries only motion energy; future revisions may add `has_face: Bool`
/// (on-device face detection) and `smile_score: Float` (emotion highlight) for
/// the Agent auto-edit slot-matching workflow — both additive Codable fields, so
/// existing JSON keeps decoding via optionals.
public struct MotionSegment: Codable, Sendable, Equatable {
    public let timestamp: Double   // 当前帧在视频中的时间戳（秒）
    public let energy: Float       // 运动能量得分：0.0（完全静止）到 100.0（剧烈运动/转场）
    
    public init(timestamp: Double, energy: Float) {
        self.timestamp = timestamp
        self.energy = energy
    }
}

public struct VideoMotionRange: Codable, Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let level: String       // "low" | "medium" | "high"
    public let avgEnergy: Float
    public let peakEnergy: Float

    public init(
        start: Double,
        end: Double,
        level: String,
        avgEnergy: Float,
        peakEnergy: Float
    ) {
        self.start = start
        self.end = end
        self.level = level
        self.avgEnergy = avgEnergy
        self.peakEnergy = peakEnergy
    }
}



/// Wraps a video URL obtained from a PhotosPicker transferable load.
public struct VideoTransferable: Transferable {
   public let url: URL

   public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

/// On-device, server-free motion-energy feature extractor.
///
/// Streams a video's frames through AVFoundation's hardware-accelerated reader and
/// scores frame-to-frame change with a green-channel pixel-residual (a cheap
/// luminance proxy). Sampling is throttled to a few frames per second so extraction
/// runs several times faster than playback with a flat memory profile.
public final class VideoMotionProfiler: Sendable {

    public static let shared = VideoMotionProfiler()
    private init() {}

    /// Mean per-pixel green-channel delta that maps to a full-scale 100 energy
    /// score. ~50 grey levels of average change already implies a hard cut or
    /// extremely violent motion. Tune here to recalibrate the whole curve.
    static let fullScaleDelta: Float = 50

    /// Analyzes a local video and produces its motion-energy curve.
    /// - Parameters:
    ///   - videoURL: a local (sandbox) video URL, e.g. from a PHPicker import.
    ///   - fpsSampling: frames sampled per second. The default of 2 fps is plenty
    ///     for editing rhythm and hard-cut detection while keeping extraction fast.
    /// - Returns: the sampled `[MotionSegment]` curve (empty if the asset is unreadable).
    public func profileMotion(at videoURL: URL, fpsSampling: Double = 2.0) async throws -> [MotionSegment] {
        let asset = AVURLAsset(url: videoURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return []
        }
        let reader = try AVAssetReader(asset: asset)
        // 32-bit BGRA keeps the per-pixel math trivial (green = byte offset 1).
        let trackOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        guard reader.canAdd(trackOutput) else { return [] }
        reader.add(trackOutput)
        guard reader.startReading() else { return [] }

        let frameInterval = 1.0 / max(0.1, fpsSampling)
        var timeline: [MotionSegment] = []
        var previousBuffer: CVPixelBuffer?
        var nextSampleTime: Double = 0

        // Stream frames; only the throttled sample points are scored. Decoding still
        // walks every frame, but the pixel math (the real cost) runs ~fpsSampling/fps.
        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }

            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard time.isFinite, time >= nextSampleTime else { continue }
            nextSampleTime += frameInterval

            guard let currentBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            if let previousBuffer {
                let delta = meanGreenDelta(from: previousBuffer, to: currentBuffer)
                timeline.append(MotionSegment(timestamp: time, energy: Self.normalize(delta)))
            } else {
                // First sample has no predecessor → energy 0.
                timeline.append(MotionSegment(timestamp: time, energy: 0))
            }
            previousBuffer = currentBuffer
        }

        return timeline
    }

    private static func normalize(_ meanDelta: Float) -> Float {
        min(max(meanDelta / fullScaleDelta * 100, 0), 100)
    }

    /// Mean absolute green-channel difference between two BGRA frames, via Accelerate.
    ///
    /// Iterates row by row using `CVPixelBufferGetBytesPerRow` so the stride
    /// correctly skips any per-row padding the decoder added — assuming a tightly
    /// packed `width * height * 4` buffer would mis-align reads on widths that
    /// aren't a multiple of the alignment unit.
    private func meanGreenDelta(from a: CVPixelBuffer, to b: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(a, .readOnly)
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(a, .readOnly)
            CVPixelBufferUnlockBaseAddress(b, .readOnly)
        }

        guard let baseA = CVPixelBufferGetBaseAddress(a),
              let baseB = CVPixelBufferGetBaseAddress(b) else { return 0 }

        // Same source track ⇒ identical dimensions; clamp defensively regardless.
        let width  = min(CVPixelBufferGetWidth(a),  CVPixelBufferGetWidth(b))
        let height = min(CVPixelBufferGetHeight(a), CVPixelBufferGetHeight(b))
        guard width > 0, height > 0 else { return 0 }

        let rowBytesA = CVPixelBufferGetBytesPerRow(a)
        let rowBytesB = CVPixelBufferGetBytesPerRow(b)
        let ptrA = baseA.assumingMemoryBound(to: UInt8.self)
        let ptrB = baseB.assumingMemoryBound(to: UInt8.self)

        // BGRA byte layout: B=0, G=1, R=2, A=3. The green channel is the cheapest
        // single-channel luminance proxy; reading it with stride 4 yields `width`
        // samples per row independent of trailing padding.
        let bgraStride: vDSP_Stride = 4
        let greenOffset = 1
        let n = vDSP_Length(width)

        // Per-call scratch reused across rows (Accelerate works on Float vectors).
        var floatA  = [Float](repeating: 0, count: width)
        var floatB  = [Float](repeating: 0, count: width)
        var rowDiff = [Float](repeating: 0, count: width)
        var totalAbsDelta: Float = 0

        for y in 0..<height {
            let rowA = ptrA + y * rowBytesA + greenOffset
            let rowB = ptrB + y * rowBytesB + greenOffset
            // Strided UInt8 green samples → contiguous Float.
            vDSP_vfltu8(rowA, bgraStride, &floatA, 1, n)
            vDSP_vfltu8(rowB, bgraStride, &floatB, 1, n)
            // rowDiff = floatA - floatB; then accumulate Σ|rowDiff|.
            vDSP_vsub(floatB, 1, floatA, 1, &rowDiff, 1, n)
            var rowSum: Float = 0
            vDSP_svemg(rowDiff, 1, &rowSum, n)   // sum of magnitudes
            totalAbsDelta += rowSum
        }

        return totalAbsDelta / Float(width * height)
    }
}


extension VideoMotionProfiler {
    
    public func profileMotionRanges(
        at videoURL: URL,
        fpsSampling: Double = 2.0,
        lowThreshold: Float = 20,
        highThreshold: Float = 55,
        minRangeDuration: Double = 0.8
    ) async throws -> [VideoMotionRange] {
        let points = try await profileMotion(at: videoURL, fpsSampling: fpsSampling)
        return Self.buildMotionRanges(
            from: points,
            lowThreshold: lowThreshold,
            highThreshold: highThreshold,
            minRangeDuration: minRangeDuration
        )
    }
    
    public static func buildMotionRanges(
        from points: [MotionSegment],
        lowThreshold: Float = 20,
        highThreshold: Float = 55,
        minRangeDuration: Double = 0.8
    ) -> [VideoMotionRange] {
        guard points.count >= 2 else { return [] }

        func level(for energy: Float) -> String {
            if energy >= highThreshold { return "high" }
            if energy >= lowThreshold { return "medium" }
            return "low"
        }

        var ranges: [VideoMotionRange] = []

        var currentLevel = level(for: points[0].energy)
        var start = points[0].timestamp
        var energies: [Float] = [points[0].energy]

        for point in points.dropFirst() {
            let nextLevel = level(for: point.energy)

            if nextLevel == currentLevel {
                energies.append(point.energy)
                continue
            }

            let end = point.timestamp
            ranges.append(makeRange(
                start: start,
                end: end,
                level: currentLevel,
                energies: energies
            ))

            start = point.timestamp
            currentLevel = nextLevel
            energies = [point.energy]
        }

        if let last = points.last {
            ranges.append(makeRange(
                start: start,
                end: last.timestamp,
                level: currentLevel,
                energies: energies
            ))
        }

        return mergeShortRanges(ranges, minDuration: minRangeDuration)
    }

    private static func makeRange(
        start: Double,
        end: Double,
        level: String,
        energies: [Float]
    ) -> VideoMotionRange {
        let safeEnd = max(end, start)
        let avg = energies.isEmpty ? 0 : energies.reduce(0, +) / Float(energies.count)
        let peak = energies.max() ?? 0

        return VideoMotionRange(
            start: round3(start),
            end: round3(safeEnd),
            level: level,
            avgEnergy: round2(avg),
            peakEnergy: round2(peak)
        )
    }
    
    private static func mergeShortRanges(
        _ ranges: [VideoMotionRange],
        minDuration: Double
    ) -> [VideoMotionRange] {
        guard ranges.count > 1 else { return ranges }

        var output: [VideoMotionRange] = []

        for range in ranges {
            let duration = range.end - range.start

            if duration >= minDuration || output.isEmpty {
                output.append(range)
                continue
            }

            // 过短段合并到前一个段，level 取更高运动等级
            let previous = output.removeLast()
            let mergedLevel = higherLevel(previous.level, range.level)
            let totalDuration = max(range.end - previous.start, 0.001)

            let prevDur = max(previous.end - previous.start, 0)
            let currDur = max(range.end - range.start, 0)

            let weightedAvg = Float(
                (Double(previous.avgEnergy) * prevDur + Double(range.avgEnergy) * currDur)
                / max(prevDur + currDur, 0.001)
            )

            output.append(VideoMotionRange(
                start: previous.start,
                end: range.end,
                level: mergedLevel,
                avgEnergy: round2(weightedAvg),
                peakEnergy: max(previous.peakEnergy, range.peakEnergy)
            ))
        }

        return output
    }

    private static func higherLevel(_ a: String, _ b: String) -> String {
        func rank(_ level: String) -> Int {
            switch level {
            case "high": return 3
            case "medium": return 2
            default: return 1
            }
        }
        return rank(a) >= rank(b) ? a : b
    }

    private static func round3(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private static func round2(_ value: Float) -> Float {
        (value * 100).rounded() / 100
    }
}
