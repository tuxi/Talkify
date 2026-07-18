//
//  CircularTaskProgressView.swift
//  DesignKit
//
//  Created by xiaoyuan on 2026/3/20.
//

import SwiftUI

public struct CircularTaskProgressView: View {
    public let progress: Double
    
    public init(progress: Double) {
        self.progress = progress
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 6)
                .frame(width: 54, height: 54)
            
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}
