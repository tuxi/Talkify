//
//  PreviewPlaybackSectionHost.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//

import SwiftUI
import CoreGraphics

public struct PreviewPlaybackSectionHost<Item, Content: View>: View {
    private let items: [Item]
    private let viewport: PreviewViewportSnapshot
    private let coordinateSpaceName: String
    private let adapter: PreviewPlaybackSectionAdapter<Item>
    private let content: (Item, PreviewPlaybackItemBinding, @escaping (VisibilitySnapshot) -> Void) -> Content

    public init(
        items: [Item],
        viewport: PreviewViewportSnapshot,
        coordinateSpaceName: String,
        adapter: PreviewPlaybackSectionAdapter<Item>,
        content: @escaping (Item, PreviewPlaybackItemBinding, @escaping (VisibilitySnapshot) -> Void) -> Content
    ) {
        self.items = items
        self.viewport = viewport
        self.coordinateSpaceName = coordinateSpaceName
        self.adapter = adapter
        self.content = content
    }

    public var body: some View {
        Group {
            contentBody
        }
        .background {
            SectionFrameReader(coordinateSpaceName: coordinateSpaceName) { frame in
                adapter.updateSectionFrame(frame)
            }
        }
        .onAppear {
            adapter.registerIfNeeded()
        }
        .onDisappear {
            adapter.unregister()
        }
        .onChange(of: viewport) { _, _ in
            adapter.pushSnapshot()
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        EmptyView()
    }

    public func visibilityReporter(for item: Item) -> (VisibilitySnapshot) -> Void {
        { snapshot in
            adapter.updateVisibility(snapshot)
        }
    }

    public func binding(for item: Item) -> PreviewPlaybackItemBinding {
        adapter.binding(for: item)
    }
}
