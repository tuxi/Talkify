//
//  DreamProButton.swift
//  DesignKit
//
//  Created by Codex on 2026/4/23.
//

import SwiftUI

@MainActor
public struct DreamProButton: View {
    public enum Appearance: Sendable {
        case immersive
        case elevated
    }

    private let title: String
    private let appearance: Appearance
    private let action: () -> Void

    public init(
        title: String = "PRO",
        appearance: Appearance,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.appearance = appearance
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(iconStyle)

                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(textStyle)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                Capsule()
                    .fill(backgroundStyle)
                    .overlay {
                        Capsule()
                            .strokeBorder(borderStyle, lineWidth: borderWidth)
                    }
                    .overlay {
                        Capsule()
                            .fill(highlightStyle)
                            .padding(1)
                            .mask(alignment: .top) {
                                Capsule()
                                    .frame(height: 16)
                            }
                    }
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        }
        .buttonStyle(DreamProButtonStyle())
        .accessibilityLabel("DreamAI Pro")
        .accessibilityHint("打开订阅中心")
    }
}

private extension DreamProButton {
    var backgroundStyle: AnyShapeStyle {
        switch appearance {
        case .immersive:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.26),
                        Color.white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        case .elevated:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "F7FBFF"),
                        Color(hex: "E8FFF8")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    var borderStyle: AnyShapeStyle {
        switch appearance {
        case .immersive:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        case .elevated:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "BCD2FF").opacity(0.95),
                        Color(hex: "8CE7D4").opacity(0.95)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    var highlightStyle: AnyShapeStyle {
        switch appearance {
        case .immersive:
            return AnyShapeStyle(Color.white.opacity(0.12))

        case .elevated:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    var textStyle: AnyShapeStyle {
        switch appearance {
        case .immersive:
            return AnyShapeStyle(Color.white.opacity(0.96))

        case .elevated:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "2B4BFF"),
                        Color(hex: "0F8E84")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    var iconStyle: AnyShapeStyle {
        switch appearance {
        case .immersive:
            return AnyShapeStyle(Color.white.opacity(0.92))

        case .elevated:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "5570FF"),
                        Color(hex: "17B5A0")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    var shadowColor: Color {
        switch appearance {
        case .immersive:
            return .black.opacity(0.12)
        case .elevated:
            return Color(hex: "6AA9FF").opacity(0.18)
        }
    }

    var shadowRadius: CGFloat {
        switch appearance {
        case .immersive:
            return 8
        case .elevated:
            return 10
        }
    }

    var shadowYOffset: CGFloat {
        switch appearance {
        case .immersive:
            return 3
        case .elevated:
            return 5
        }
    }

    var borderWidth: CGFloat {
        switch appearance {
        case .immersive:
            return 0.9
        case .elevated:
            return 1
        }
    }
}

private struct DreamProButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}
