//
//  LiquidGlass.swift
//  invis
//
//  Apple Human Interface Guidelines: Liquid Glass Design System.
//  Provides translucent glass materials, specular refraction borders,
//  haptic feedback triggers, and refined typography.
//

import SwiftUI

// MARK: - Liquid Glass Card Modifier
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var interactive: Bool

    public init(cornerRadius: CGFloat = 18, interactive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Liquid Glass Capsule Modifier
public struct LiquidGlassCapsuleModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.36),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - View Extension Convenience
public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCapsule() -> some View {
        modifier(LiquidGlassCapsuleModifier())
    }
}

// MARK: - Haptic Utilities
public enum HapticFeedback {
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    public static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
