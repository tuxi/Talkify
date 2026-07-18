//
//  ImagePreviewSheet1.swift
//  DesignKit
//
//  Created by xiaoyuan on 2026/4/20.
//

import SwiftUI
import Kingfisher
import CoreKit

public struct ImagePreviewSheet1: View {
    let imageURL: URL
    @Environment(\.dismiss) var dismiss
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    public init(url: URL) {
        self.imageURL = url
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if imageURL.isFileURL {
                    localImageView
                } else {
                    remoteImageView
                }
            }
            .toolbar {
                ToolbarItem(placement: platformPlacement(isLeading: true)) {
                    Button {
                        Task { await saveImage() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                
                ToolbarItem(placement: platformPlacement(isLeading: false)) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var remoteImageView: some View {
        KFImage(imageURL)
            .placeholder { ProgressView().tint(.white) }
            .resizable()
            .aspectRatio(contentMode: .fit)
            .zoomable()
    }

    private var localImageView: some View {
        Group {
            if let uiImage = MyImage(contentsOfFile: imageURL.path) {
                Image(myImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .zoomable()
            } else {
                Text("无法读取本地图片").foregroundColor(.gray)
            }
        }
    }

    // 使用 Async/Await 处理保存
    @MainActor
    private func saveImage() async {
        do {
            let uiImage: MyImage?
            if imageURL.isFileURL {
                uiImage = MyImage(contentsOfFile: imageURL.path)
            } else {
                // Kingfisher 缓存提取
                let result = try await KingfisherManager.shared.retrieveImage(with: imageURL)
                uiImage = result.image
            }

            if let image = uiImage {
                try await PhotoStore.saveImage(image)
                alertMessage = "已保存到相册"
            } else {
                alertMessage = "图片损坏或无法获取"
            }
        } catch {
            alertMessage = error.localizedDescription
        }
        showingAlert = true
    }
}

struct ZoomableModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .scaleEffect(scale)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale *= delta
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1.0 {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    withAnimation(.spring()) {
                        if scale != 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                        }
                    }
                }
            )
    }
}

extension View {
    func zoomable() -> some View {
        self.modifier(ZoomableModifier())
    }
    
    func platformPlacement(isLeading: Bool) -> ToolbarItemPlacement {
        #if os(iOS)
        return isLeading ? .navigationBarLeading : .navigationBarTrailing
        #else
        // macOS 对应位置
        return isLeading ? .navigation : .confirmationAction
        #endif
    }
}
