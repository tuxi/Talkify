//
//  PreviewScrollSignal.swift
//  CoreKit
//
//  Created by Codex on 2026/4/23.
//

import CoreGraphics
import Foundation

public struct PreviewScrollSignal: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case idle
        case up
        case down
    }

    public let verticalVelocity: CGFloat
    public let isDragging: Bool
    public let timestamp: Date

    public init(
        verticalVelocity: CGFloat,
        isDragging: Bool,
        timestamp: Date = Date()
    ) {
        self.verticalVelocity = verticalVelocity
        self.isDragging = isDragging
        self.timestamp = timestamp
    }

    public var direction: Direction {
        guard abs(verticalVelocity) > 1 else { return .idle }
        return verticalVelocity > 0 ? .down : .up
    }

    public static let idle = PreviewScrollSignal(verticalVelocity: 0, isDragging: false)
}
