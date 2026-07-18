//
//  PlayerContainerView.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/20.
//

import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
public typealias PlatformViewRepresentable = UIViewRepresentable
public typealias PlatformView = UIView
#elseif os(macOS)
import AppKit
public typealias PlatformViewRepresentable = NSViewRepresentable
public typealias PlatformView = NSView
#endif

public struct PlayerContainerView: PlatformViewRepresentable {
    public let player: AVPlayer
    
    public init(player: AVPlayer) {
        self.player = player
    }
    
    #if os(iOS)
    public func makeUIView(context: Context) -> PlayerHostingView {
        let view = PlayerHostingView()
        view.playerLayer.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    
    public func updateUIView(_ uiView: PlayerHostingView, context: Context) {
        uiView.player = player
    }
    #elseif os(macOS)
    public func makeNSView(context: Context) -> PlayerHostingView {
        let view = PlayerHostingView()
        view.playerLayer.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    
    public func updateNSView(_ nsView: PlayerHostingView, context: Context) {
        nsView.player = player
    }
    #endif
}

public final class PlayerHostingView: PlatformView {
    
    #if os(iOS)
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    #elseif os(macOS)
    public override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }
    #endif
    
    public var playerLayer: AVPlayerLayer {
        #if os(iOS)
        return layer as! AVPlayerLayer
        #elseif os(macOS)
        return layer as! AVPlayerLayer
        #endif
    }
    
    public var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    #if os(macOS)
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    #endif
}
