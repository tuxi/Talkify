//
//  AudioBeatProfiler.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/6/9.
//
//  V2.0 reverse templating — audio axis. Extracts a video's audio track,
//  runs a low-frequency (20–150 Hz) FFT energy analysis via Accelerate.vDSP,
//  and reports bass-drum / kick onsets as [AudioBeatPoint].
//

import Foundation
import AVFoundation
import Accelerate

/// A detected low-frequency onset (bass drum / kick).
public struct AudioBeatPoint: Codable, Sendable, Equatable {
    public let timestamp: Double      // 鼓点绝对时间戳（秒）
    public let dbChangeRatio: Float   // 能量突变倍数 E_current / E_previous
    
    public init(timestamp: Double, dbChangeRatio: Float) {
        self.timestamp = timestamp
        self.dbChangeRatio = dbChangeRatio
    }
}

/// On-device low-frequency onset detector. Stateless singleton.
public final class AudioBeatProfiler: Sendable {

    public static let shared = AudioBeatProfiler()
    private init() {}

    /// Audio is resampled to this rate so FFT bin → frequency mapping is deterministic.
    static let sampleRate: Double = 44_100
    /// FFT window size (power of two). 1024 @ 44.1k ≈ 23 ms — within the 20–30 ms spec.
    static let fftSize: Int = 1024
    /// 50% overlap → ~11.6 ms onset timing resolution.
    static let hopSize: Int = 512
    /// Low band, in Hz — the absolute home of kick / bass.
    static let bandLowHz: Double = 20
    static let bandHighHz: Double = 150
    /// ΔE ratio above which a frame is flagged as a beat (PRD baseline 2.5–3.5).
    static let beatRatioThreshold: Float = 2.5
    /// Minimum gap between beats so one transient isn't double-counted.
    static let refractory: Double = 0.12

    /// Extracts the audio and returns its low-frequency onset timeline.
    public func profileBeats(at videoURL: URL) async throws -> [AudioBeatPoint] {
        let samples = try await decodePCM(at: videoURL)
        guard samples.count >= Self.fftSize else { return [] }
        return detectBeats(in: samples)
    }

    // MARK: - PCM extraction (Linear PCM Float32, mono)

    private func decodePCM(at url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: Self.sampleRate
        ])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var samples: [Float] = []
        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else {
                CMSampleBufferInvalidate(sample)
                continue
            }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length,
                                        totalLengthOut: nil, dataPointerOut: &dataPointer)
            if let dataPointer {
                let count = length / MemoryLayout<Float>.size
                dataPointer.withMemoryRebound(to: Float.self, capacity: count) { fptr in
                    samples.append(contentsOf: UnsafeBufferPointer(start: fptr, count: count))
                }
            }
            CMSampleBufferInvalidate(sample)
        }
        return samples
    }

    // MARK: - Onset detection

    private func detectBeats(in samples: [Float]) -> [AudioBeatPoint] {
        let n = Self.fftSize
        let halfN = n / 2
        let log2n = vDSP_Length(log2(Double(n)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        let binWidth = Self.sampleRate / Double(n)
        let bandLow  = max(1, Int((Self.bandLowHz  / binWidth).rounded(.down)))
        let bandHigh = min(halfN - 1, Int((Self.bandHighHz / binWidth).rounded(.up)))

        // Pass 1: per-frame low-band energy.
        var energies: [Float] = []
        var times: [Double] = []
        var windowed = [Float](repeating: 0, count: n)
        var frameStart = 0
        while frameStart + n <= samples.count {
            samples.withUnsafeBufferPointer { sp in
                vDSP_vmul(sp.baseAddress! + frameStart, 1, hann, 1, &windowed, 1, vDSP_Length(n))
            }
            energies.append(bandEnergy(windowed: windowed, setup: setup, log2n: log2n,
                                       halfN: halfN, bandLow: bandLow, bandHigh: bandHigh))
            times.append(Double(frameStart + n / 2) / Self.sampleRate)
            frameStart += Self.hopSize
        }

        guard energies.count > 1 else { return [] }
        let mean = energies.reduce(0, +) / Float(energies.count)
        guard mean > 0 else { return [] }
        let floor = mean              // only above-average frames qualify as a hit

        // Pass 2: first-difference ratio detection with a refractory gap.
        var beats: [AudioBeatPoint] = []
        var lastBeat = -Double.infinity
        for i in 1..<energies.count {
            let current = energies[i]
            let previous = max(energies[i - 1], mean * 0.01)   // guard silence blow-up
            let ratio = current / previous
            if ratio > Self.beatRatioThreshold,
               current > floor,
               times[i] - lastBeat >= Self.refractory {
                beats.append(AudioBeatPoint(timestamp: times[i], dbChangeRatio: ratio))
                lastBeat = times[i]
            }
        }
        return beats
    }

    /// Forward real FFT of one windowed frame → summed squared magnitude over the
    /// `[bandLow, bandHigh]` bins (the low-frequency energy E for this frame).
    private func bandEnergy(
        windowed: [Float],
        setup: FFTSetup,
        log2n: vDSP_Length,
        halfN: Int,
        bandLow: Int,
        bandHigh: Int
    ) -> Float {
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var mags  = [Float](repeating: 0, count: halfN)
        var energy: Float = 0

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)

                // Pack the real samples into split-complex form.
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(halfN))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                mags.withUnsafeMutableBufferPointer { mp in
                    vDSP_zvmags(&split, 1, mp.baseAddress!, 1, vDSP_Length(halfN))
                    let lo = max(1, bandLow)            // skip DC bin 0
                    let hi = min(halfN - 1, bandHigh)
                    if lo <= hi {
                        vDSP_sve(mp.baseAddress! + lo, 1, &energy, vDSP_Length(hi - lo + 1))
                    }
                }
            }
        }
        return energy
    }
}
