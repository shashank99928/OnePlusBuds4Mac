import SwiftUI

/// The app's visual language: a dark, blue-tinted "night" surface with translucent
/// cards, a single bright accent, and soft glows — the smart-home / car-console look.
///
/// The palette is deliberately explicit rather than semantic, because the design
/// assumes a dark surface: the app pins itself to dark appearance (see `AppDelegate`)
/// so these values are what actually render, on any machine.
enum Theme {
    /// Primary accent — the bright blue used for anything active or selected.
    static let accent = Color(red: 0.36, green: 0.60, blue: 1.00)
    /// Deeper accent for gradients and pressed states.
    static let accentDeep = Color(red: 0.16, green: 0.36, blue: 0.95)

    /// Background gradient, top to bottom.
    static let backgroundTop = Color(red: 0.055, green: 0.125, blue: 0.285)
    static let backgroundBottom = Color(red: 0.027, green: 0.055, blue: 0.150)

    /// Translucent card fill and hairline stroke.
    static let card = Color.white.opacity(0.075)
    static let cardStroke = Color.white.opacity(0.10)
    /// A slightly stronger surface, for chips that need to read against a card.
    static let chip = Color.white.opacity(0.10)

    /// Text that is present but not shouting.
    static let secondary = Color.white.opacity(0.60)

    /// The fill behind a *selected* control.
    ///
    /// Deliberately not `accent`. White on the bright accent measures 2.82:1, and compositing
    /// its usual 0.9 opacity over this background only brings it to 3.2:1 — under WCAG AA's
    /// 4.5:1 for the 13pt labels these fills carry, and under even the 3:1 floor for non-text
    /// contrast. Every selected mode pill, level capsule and EQ segment was failing. This
    /// deeper blue measures 5.29:1 against white and is still unmistakably the blue one.
    /// `accent` stays for glyphs, strokes and glows, where it sits on the dark surface and
    /// passes at 5.2:1.
    static let selection = Color(red: 0.16, green: 0.36, blue: 0.95)

    /// The hairline around a selected control, so its edge reads without relying on hue alone.
    static let selectionStroke = Color.white.opacity(0.45)

    /// "Live" indicator — connected, healthy.
    static let green = Color(red: 0.24, green: 0.86, blue: 0.55)
}

/// Full-bleed background: a deep vertical gradient with a blue glow near the top and a
/// slightly darker floor, so cards float on it.
struct PremiumBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom],
                startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [Theme.accent.opacity(0.32), .clear],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 8, endRadius: 460)

            RadialGradient(
                colors: [Theme.accentDeep.opacity(0.22), .clear],
                center: UnitPoint(x: 0.1, y: 0.95),
                startRadius: 4, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// The standard frosted card: translucent fill, hairline stroke.
    func premiumCard(cornerRadius: CGFloat = 20, fill: Color = Theme.card) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1))
    }

    /// Applied to a window's root so the whole surface reads as the "night" design.
    func premiumSurface() -> some View {
        self
            .foregroundStyle(.white)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
    }
}
