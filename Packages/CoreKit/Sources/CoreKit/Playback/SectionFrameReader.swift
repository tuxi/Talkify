//
//  SectionFrameReader.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import SwiftUI

private struct SectionFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

public struct SectionFrameReader: View {
    public let coordinateSpaceName: String
    public let onChange: (CGRect) -> Void

    public init(coordinateSpaceName: String, onChange: @escaping (CGRect) -> Void) {
        self.coordinateSpaceName = coordinateSpaceName
        self.onChange = onChange
    }
    
    public var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: SectionFramePreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
        }
        .onPreferenceChange(SectionFramePreferenceKey.self, perform: onChange)
    }
}
