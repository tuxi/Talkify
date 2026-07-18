//
//  SwiftUIView.swift
//  DesignKit
//
//  Created by xiaoyuan on 2026/4/1.
//

import SwiftUI

/// 支持 Swift 6 的高级简约分段选择器
@MainActor
public struct DreamSegmentControl<Option: Hashable & Identifiable>: View where Option.ID: Sendable {
    
    // MARK: - Properties
    @Environment(\.colorScheme) private var colorScheme
    @Binding private var selection: Option?
    private let options: [Option]
    private let titleKeyPath: KeyPath<Option, String>
    
    @Namespace private var activeTag // 命名空间用于平滑位移
    
    public init(
        selection: Binding<Option?>,
        options: [Option],
        titleKeyPath: KeyPath<Option, String>
    ) {
        self._selection = selection
        self.options = options
        self.titleKeyPath = titleKeyPath
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection?.id == option.id
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    Text(option[keyPath: titleKeyPath])
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(colorScheme == .light ? .white : Color(white: 0.25))
                            .shadow(color: .black.opacity(colorScheme == .light ? 0.05 : 0.2), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "ACTIVETAB", in: activeTag)
                    }
                }
            }
        }
        .padding(4)
        .background {
            // 奶昔背景底色
            Capsule()
                .fill(colorScheme == .light ? Color(white: 0.95) : Color(white: 0.15))
        }
        .sensoryFeedback(.selection, trigger: selection) // 增加触感反馈
    }
}
