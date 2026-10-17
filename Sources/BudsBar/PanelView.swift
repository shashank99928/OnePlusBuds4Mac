import AppKit
import SwiftUI

/// The compact surface that hangs off the menu-bar item: the same controls as the main
/// window, condensed to a fixed narrow column for at-a-glance use.
struct PanelView: View {
    @Bindable var buds: Buds

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    DeviceHeader(buds: buds)
                    PowerButton(buds: buds)
                }

                if buds.isConnected {
                    BatteryChipsRow(buds: buds)
                    NoiseControlSection(buds: buds)
                } else {
                    BudsDisconnectedNote(buds: buds)
                }

                if let error = buds.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .premiumSurface()
        // The popover re-adds this view to a window each time it opens, so onAppear is a
        // per-open hook: the panel always shows live state, not whatever it last rendered.
        .onAppear { buds.refreshConnectionState() }
        .animation(.smooth(duration: 0.28), value: buds.isConnected)
        .animation(.smooth(duration: 0.28), value: buds.battery.enclosure == nil)
        .animation(.smooth(duration: 0.28), value: buds.battery.left)
        .animation(.smooth(duration: 0.28), value: buds.battery.right)
        .animation(.smooth(duration: 0.28), value: buds.placement.left)
        .animation(.smooth(duration: 0.28), value: buds.placement.right)
    }
}
