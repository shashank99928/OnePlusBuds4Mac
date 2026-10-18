import SwiftUI

/// Compact AirPods-style battery card shown in a floating panel when the buds connect.
struct FloatingBatteryView: View {
    @Bindable var buds: Buds

    /// `.glassEffect` is a compositor effect, and `ImageRenderer` draws nothing at all for it —
    /// not the capsule and not the text inside it, so a golden of this card came out blank and
    /// would have passed forever. While a snapshot is being drawn the capsule is painted as a
    /// plain translucent shape instead, which is what lets the component goldens pin the
    /// padding, the cell count and the type that a change would actually break. The app pins
    /// itself to dark appearance (`NSApp.appearance`), so the substitute is drawn in the light
    /// the real card always sees. Nothing in a running app enters this branch.
    @Environment(\.isRenderingSnapshot) private var isSnapshot

    var body: some View {
        card(content
                .padding(.horizontal, 18)
                .padding(.vertical, 12))
    }

    @ViewBuilder
    private func card<V: View>(_ inner: V) -> some View {
        if isSnapshot {
            inner
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
        } else {
            inner.glassEffect(.regular, in: .capsule)
        }
    }

    /// True in the instant the popup opens: the link is up but the control channel has not
    /// opened, so both buds would draw a bare "—" with nothing to explain it. That is the
    /// state the panel's battery row now labels, seen here from the menu bar.
    private var isWaitingForBattery: Bool {
        buds.battery.left == nil && buds.battery.right == nil && !buds.isControlChannelOpen
    }

    @ViewBuilder
    private var content: some View {
        if isWaitingForBattery {
            // A `ControlsNotReady`-style line, but with an adaptive secondary rather than
            // `Theme.secondary`: this card is a glass capsule over the desktop and is not
            // pinned to the app's dark surface, so a fixed white would wash out in light mode.
            Text("Reading the battery…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 14) {
                floatingCell(glyph: "earbud.left", title: "L", name: "Left earbud",
                             value: buds.battery.left)
                floatingCell(glyph: "earbud.right", title: "R", name: "Right earbud",
                             value: buds.battery.right)
                if buds.battery.enclosure != nil {
                    floatingCell(glyph: "earbuds.case.fill", title: "Case", name: "Case",
                                 value: buds.battery.enclosure)
                }
            }
        }
    }

    private func floatingCell(glyph: String, title: String, name: String,
                              value: Int?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.system(size: 18, weight: .regular))
                .accessibilityHidden(true)
            // "—%" is a placeholder with a unit glued to it, which reads as a broken value
            // rather than a missing one. A bare dash says the same thing without pretending
            // there is a number behind it.
            Text(value.map { "\($0)%" } ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(value.map { "\($0) percent" } ?? "Not reported")
    }
}
