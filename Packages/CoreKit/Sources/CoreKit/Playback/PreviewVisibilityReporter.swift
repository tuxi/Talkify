//
//  PreviewVisibilityReporter.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import SwiftUI

public struct PreviewVisibilityReporter: ViewModifier {
    let id: String
    let coordinateSpaceName: String
    let viewport: PreviewViewportSnapshot
    let onUpdate: (VisibilitySnapshot) -> Void

    public func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        report(proxy: proxy)
                    }
                    .onChange(of: proxy.frame(in: .named(coordinateSpaceName))) { _, _ in
                        report(proxy: proxy)
                    }
                    .onChange(of: viewport) { _, _ in
                        report(proxy: proxy)
                    }
            }
        }
    }

    private func report(proxy: GeometryProxy) {
        let frame = proxy.frame(in: .named(coordinateSpaceName))
        let viewportRect = viewport.rect

        guard frame.width > 0,
              frame.height > 0,
              viewportRect.width > 0,
              viewportRect.height > 0 else {
            return
        }

        let intersection = frame.intersection(viewportRect)
        let visibleArea = max(0, intersection.width) * max(0, intersection.height)
        let totalArea = frame.width * frame.height
        let ratio = totalArea > 0 ? visibleArea / totalArea : 0
        let horizontalDistance = abs(frame.midX - viewportRect.midX)
        let verticalDistance = abs(frame.midY - viewportRect.midY)

        let snapshot = VisibilitySnapshot(
            id: id,
            visibleRatio: ratio,
            horizontalDistanceToViewportCenter: horizontalDistance,
            verticalDistanceToViewportCenter: verticalDistance,
            isVisible: !intersection.isNull && ratio > 0,
            frame: frame
        )

        onUpdate(snapshot)
    }
}

public extension View {
    func previewVisibilityReporter(
        id: String,
        coordinateSpaceName: String,
        viewport: PreviewViewportSnapshot,
        onUpdate: @escaping (VisibilitySnapshot) -> Void
    ) -> some View {
        modifier(
            PreviewVisibilityReporter(
                id: id,
                coordinateSpaceName: coordinateSpaceName,
                viewport: viewport,
                onUpdate: onUpdate
            )
        )
    }
}
