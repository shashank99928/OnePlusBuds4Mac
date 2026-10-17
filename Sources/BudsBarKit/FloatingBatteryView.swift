import SwiftUI

/// Compact AirPods-style battery card shown in a floating panel when the buds connect.
struct FloatingBatteryView: View {
    @Bindable var buds: Buds

    var body: some View {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
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
