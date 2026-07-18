//
//  JSONViewerSheet.swift
//  DesignKit
//
//  Created by xiaoyuan on 2026/5/25.
//

import SwiftUI
import DesignKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct JSONViewerSheet: View {
    public let title: String
    public let jsonString: String
    @Environment(\.dismiss) private var dismiss
    
    public init(title: String, jsonString: String) {
        self.title = title
        self.jsonString = jsonString
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                Text(jsonString)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.underPageBackground)
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: leadingToolbarPlacement) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: toolbarActionPlacement) {
                    Button {
                        copyJSONString()
                        ToastContext.shared.show("已复制到剪贴板", icon: "doc.on.doc.fill")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
    
    var toolbarActionPlacement: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .topBarTrailing
#endif
    }
    
    var leadingToolbarPlacement: ToolbarItemPlacement {
#if os(macOS)
        .cancellationAction
#else
        .topBarLeading
#endif
    }
    
    func copyJSONString() {
#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonString, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = jsonString
#endif
    }
}


public struct JSONViewerPayload: Identifiable {
    public let id = UUID()
    public let title: String
    public let content: String
    
    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}
