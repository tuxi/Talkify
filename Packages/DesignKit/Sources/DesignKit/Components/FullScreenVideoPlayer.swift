//
//  FullScreenVideoPlayer.swift
//  FeatureVideoGen
//
//  Created by xiaoyuan on 2026/4/9.
//

import SwiftUI
import AVFoundation
import CoreKit

public struct FullScreenVideoPlayer: View {
    public let url: URL
    public let title: String // 增加标题属性
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Player State
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var progress: Double = 0
    @State private var isDragging = false
    
    private var showTopNavigationBar = true
    
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var controlTimer: Timer?

    public init(url: URL, title: String, showTopNavigationBar: Bool = true) {
        self.url = url
        self.title = title
        self._player = State(initialValue: VideoCachePlayer.player(for: url))
        self.showTopNavigationBar = showTopNavigationBar
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. 播放器底层
            PlayerLayerContainer(player: player, videoGravity: .resizeAspect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls.toggle()
                    }
                }
            
            // 2. 常驻顶部工具栏 (不随 showControls 隐藏)
            if showTopNavigationBar {
                VStack {
                    topNavigationBar
                    Spacer()
                }
            }
            
            // 3. 自动隐藏的底部控制栏
            VStack {
                Spacer()
                if showControls {
                    bottomControlBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player.pause()
            // 页面关闭时不需要继续下载，可以调用取消
             VideoCacheManager.shared.cancelDownload(for: url)
        }
        // 处理后台切换逻辑
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            currentTime = player.currentTime().seconds
            duration = player.currentItem?.duration.seconds ?? 0
        }
#if os(iOS)
        .statusBar(hidden: !showControls)
#endif
    }
}

// MARK: - Subviews
private extension FullScreenVideoPlayer {
    
    // 始终显示的顶部导航
    var topNavigationBar: some View {
        HStack(spacing: 15) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 10) // 考虑到安全区域由系统处理或手动微调
    }
    
    var bottomControlBar: some View {
        VStack(spacing: 15) {
            // 改进后的进度条
            VideoProgressBar(value: $progress, player: player, isDragging: $isDragging) {
                // 拖动开始或结束时重置隐藏计时器
                resetControlTimer()
            }
            
            HStack(spacing: 25) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Text("\(formatTime(seconds: currentTime)) / \(formatTime(seconds: duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    player.seek(to: .zero)
                    player.play()
                    isPlaying = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 5)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.horizontal)
        .padding(.bottom, 30)
    }
}

// MARK: - Logic Helpers
private extension FullScreenVideoPlayer {
    func setupPlayer() {
        player.play()
        isPlaying = true
        resetControlTimer()
        
        // 循环播放设置
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            Task { @MainActor in
                player.seek(to: .zero)
                player.play()
                isPlaying = true
            }
        }
    }
    
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            player.pause()
            isPlaying = false
        case .active:
            // 返回前台继续循环播放
            player.play()
            isPlaying = true
        default:
            break
        }
    }
    
    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        resetControlTimer()
    }
    
    func resetControlTimer() {
        controlTimer?.invalidate()
        // 拖动时不自动隐藏
        guard !isDragging else { return }
        
        controlTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation {
                    if isPlaying && !isDragging {
                        showControls = false
                    }
                }
            }
        }
    }
    
    func formatTime(seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - 强化版进度条
struct VideoProgressBar: View {
    @Binding var value: Double
    let player: AVPlayer
    @Binding var isDragging: Bool
    var onInteraction: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景轨道 (增加感应高度)
                Rectangle()
                    .foregroundColor(.white.opacity(0.2))
                    .frame(height: 4)
                
                // 进度轨道
                Rectangle()
                    .foregroundColor(.orange)
                    .frame(width: geometry.size.width * CGFloat(value), height: 4)
                
                // 拖动滑块 (视觉反馈)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: geometry.size.width * CGFloat(value) - 6)
                    .shadow(radius: 2)
                    .opacity(isDragging ? 1 : 0)
            }
            .frame(maxHeight: .infinity) // 填满高度以便手势捕捉
            .contentShape(Rectangle()) // 关键：扩大手势识别区域
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            player.pause() // 拖动时暂停播放，体验更丝滑
                        }
                        onInteraction()
                        let percent = Double(gesture.location.x / geometry.size.width)
                        value = max(0, min(1, percent))
                        
                        // 实时跳转预览 (可选)
                        let duration = player.currentItem?.duration.seconds ?? 0
                        let targetTime = duration * value
                        player.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    .onEnded { _ in
                        isDragging = false
                        player.play() // 拖动结束恢复播放
                        onInteraction()
                    }
            )
        }
        .frame(height: 24) // 外部容器高度，决定了手指点击的灵敏范围
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if !isDragging {
                let duration = player.currentItem?.duration.seconds ?? 0
                if duration > 0 {
                    value = player.currentTime().seconds / duration
                }
            }
        }
    }
}
