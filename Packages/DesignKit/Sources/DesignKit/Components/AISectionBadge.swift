import SwiftUI

public struct AISectionBadge: View {
    let label: String

    public init(label: String = "AI 生成示例") {
        self.label = label
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(.secondary)
    }
}
