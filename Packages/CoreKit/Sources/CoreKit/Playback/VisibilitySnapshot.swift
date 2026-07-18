//
//  VisibilitySnapshot.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import CoreGraphics

public struct VisibilitySnapshot: Equatable, Sendable, Identifiable {
    public let id: String
    public let visibleRatio: CGFloat
    public let horizontalDistanceToViewportCenter: CGFloat
    public let verticalDistanceToViewportCenter: CGFloat
    public let isVisible: Bool
    public let frame: CGRect

    public init(
        id: String,
        visibleRatio: CGFloat,
        horizontalDistanceToViewportCenter: CGFloat,
        verticalDistanceToViewportCenter: CGFloat,
        isVisible: Bool,
        frame: CGRect
    ) {
        self.id = id
        self.visibleRatio = visibleRatio
        self.horizontalDistanceToViewportCenter = horizontalDistanceToViewportCenter
        self.verticalDistanceToViewportCenter = verticalDistanceToViewportCenter
        self.isVisible = isVisible
        self.frame = frame
    }
}
