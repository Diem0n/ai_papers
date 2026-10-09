//
//  DesignSystem.swift
//  AIPapers
//
//  One shared card look instead of each screen inventing its own flat-fill
//  recipe. Change the gradient/border here, every card updates.
//

import SwiftUI

private struct SurfaceCard: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Color.primary.opacity(0.07), Color.primary.opacity(0.025)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension View {
    func surfaceCard(radius: CGFloat = 12) -> some View { modifier(SurfaceCard(radius: radius)) }

    /// A faint accent-tinted wash behind a window's content — adds depth to
    /// what would otherwise be a flat system background.
    func windowWash() -> some View {
        background(
            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                center: .topLeading, startRadius: 0, endRadius: 900
            )
            .background(.background)
        )
    }
}
