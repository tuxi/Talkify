//
//  PreviewViewportSnapshot.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import CoreGraphics

public struct PreviewViewportSnapshot: Equatable, Sendable {
    public let rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }

    public static let zero = PreviewViewportSnapshot(rect: .zero)
}
