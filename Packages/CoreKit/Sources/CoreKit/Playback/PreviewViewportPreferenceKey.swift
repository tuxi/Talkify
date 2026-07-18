//
//  PreviewViewportPreferenceKey.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import SwiftUI

private struct PreviewViewportPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

public struct PreviewViewportReader: View {
    let coordinateSpaceName: String
    let onChange: (PreviewViewportSnapshot) -> Void

    public init(
        coordinateSpaceName: String,
        onChange: @escaping (PreviewViewportSnapshot) -> Void
    ) {
        self.coordinateSpaceName = coordinateSpaceName
        self.onChange = onChange
    }

    public var body: some View {
        
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: PreviewViewportPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
        }
        .onPreferenceChange(PreviewViewportPreferenceKey.self) { rect in
            onChange(.init(rect: rect))
        }
    }
}
