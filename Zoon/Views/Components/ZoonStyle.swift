import SwiftUI

/// Shared visual vocabulary.
///
/// Small on purpose. The app leans on system materials, SF Symbols, and Dynamic
/// Type rather than a bespoke design system — it inherits dark mode, contrast
/// settings, and accessibility text sizes for free, which a hand-rolled palette
/// would have to reimplement and would get wrong.
enum ZoonStyle {

    static let cardCornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let stackSpacing: CGFloat = 16

    /// Stage colours. Ordered deep → light, matching how the stages are read.
    enum Stage {
        static let deep = Color.indigo
        static let rem = Color.purple
        static let core = Color.blue
        static let awake = Color.orange
        static let unspecified = Color.teal

        static func color(for stage: SleepStage) -> Color {
            switch stage {
            case .deep: deep
            case .rem: rem
            case .core: core
            case .awake: awake
            case .unspecified: unspecified
            case .inBed: .gray
            }
        }
    }

    static func scoreColor(_ band: SleepScore.Band) -> Color {
        switch band {
        case .excellent: .green
        case .good: .mint
        case .fair: .yellow
        case .poor: .orange
        }
    }
}

/// The rounded-material card used throughout the app.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(ZoonStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ZoonStyle.cardCornerRadius))
    }
}

extension View {
    func zoonCard() -> some View { modifier(CardBackground()) }
}

/// Badge marking synthetic data.
///
/// Present so a Simulator screenshot can never be mistaken for a real night —
/// which matters more than usual for a health app, where a fabricated number
/// shown as real is a genuine harm.
struct MockDataBadge: View {
    var body: some View {
        Label("Sample data", systemImage: "wand.and.stars")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(.tint)
    }
}

#Preview("Card") {
    VStack(spacing: 16) {
        Text("A card").zoonCard()
        MockDataBadge()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
