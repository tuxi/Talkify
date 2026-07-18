import SwiftUI

public struct AIBadge: View {
    public init() {}

    public var body: some View {
        Text("AI 生成")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
    }
}
