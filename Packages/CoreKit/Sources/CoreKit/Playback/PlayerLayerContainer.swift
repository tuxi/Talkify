//
//  PlayerLayerContainer.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

public struct PlayerLayerContainer: UIViewRepresentable {
    public let player: AVPlayer
    public var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    public var onReadyForDisplay: (() -> Void)?

    public init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        onReadyForDisplay: (() -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.onReadyForDisplay = onReadyForDisplay
    }

    public func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        view.onReadyForDisplay = onReadyForDisplay
        view.startObserving()
        return view
    }

    public func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
        uiView.onReadyForDisplay = onReadyForDisplay
    }
}

public final class PlayerView: UIView {
    override public static var layerClass: AnyClass { AVPlayerLayer.self }

    public var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    public var onReadyForDisplay: (() -> Void)?

    private var observation: NSKeyValueObservation?

    func startObserving() {
        observation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay else { return }
            self.onReadyForDisplay?()
        }
    }

    deinit {
        observation?.invalidate()
    }
}
#elseif os(macOS)
import AppKit

public struct PlayerLayerContainer: NSViewRepresentable {
    public let player: AVPlayer
    public var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    public var onReadyForDisplay: (() -> Void)?

    public init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        onReadyForDisplay: (() -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.onReadyForDisplay = onReadyForDisplay
    }

    public func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        view.onReadyForDisplay = onReadyForDisplay
        view.startObserving()
        return view
    }

    public func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.playerLayer.player = player
        nsView.playerLayer.videoGravity = videoGravity
        nsView.onReadyForDisplay = onReadyForDisplay
    }
}

public final class PlayerNSView: NSView {
    public var onReadyForDisplay: (() -> Void)?
    private var observation: NSKeyValueObservation?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = AVPlayerLayer()
    }

    public var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func startObserving() {
        observation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay else { return }
            self.onReadyForDisplay?()
        }
    }

    deinit {
        observation?.invalidate()
    }
}
#endif
