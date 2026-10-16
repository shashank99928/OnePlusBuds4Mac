import SwiftUI

/// Compact AirPods-style battery card shown in a floating panel when the buds connect.
struct FloatingBatteryView: View {
    @Bindable var buds: Buds

    var body: some View {
        HStack(spacing: 14) {
            floatingCell(glyph: "airpods.gen3", title: "L", value: buds.battery.left)
            floatingCell(glyph: "airpods.gen3", title: "R", value: buds.battery.right)
            if buds.battery.enclosure != nil {
                floatingCell(glyph: "airpods.pro.chargingcase.wireless.fill", title: "Case", value: buds.battery.enclosure)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }

    private func floatingCell(glyph: String, title: String, value: Int?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.system(size: 18, weight: .regular))
            Text(value.map { "\($0)%" } ?? "—%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
    }
}
