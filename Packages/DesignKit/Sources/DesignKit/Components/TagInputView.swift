//
//  TagInputView.swift
//  FeatureAdminUI
//
//  Created by xiaoyuan on 2026/4/4.
//

import SwiftUI

// 标签输入控件
public struct TagInputView: View {
    public let title: String
    @Binding public var tags: [String]
    @State private var newTag: String = ""

    public init(title: String, tags: Binding<[String]>) {
        self.title = title
        _tags = tags
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            
            // 已有标签流式布局
            FlowLayout() {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.subheadline)
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
            }
            
            // 输入框
            HStack {
                TextField("添加新选项...", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                
                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(newTag.isEmpty)
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            newTag = ""
        }
    }
}
