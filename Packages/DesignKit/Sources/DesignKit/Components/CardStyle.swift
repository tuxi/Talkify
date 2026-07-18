//
//  CardStyle.swift
//  DesignKit
//
//  Created by xiaoyuan on 2026/4/17.
//

import SwiftUI

public extension View {
    func cardStyle(cornerRadius: CGFloat = 24, lineWidth: CGFloat = 1) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.systemBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: lineWidth)
                )
        )
    }
}
