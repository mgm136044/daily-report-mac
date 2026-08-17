import SwiftUI

/// Design tokens.
enum Design {
    static let accent = Color(red: 0.35, green: 0.65, blue: 1.0)
    static let cardCorner: CGFloat = 12
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
}

extension View {
    /// The signature card look: material fill + conditional accent stroke.
    func card(active: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: Design.cardCorner)
                .fill(active ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: Design.cardCorner)
                    .stroke(active ? Design.accent.opacity(0.5) : .clear, lineWidth: 1)))
    }
}
