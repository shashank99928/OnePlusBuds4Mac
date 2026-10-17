import AppKit
import SwiftUI

/// The compact surface that hangs off the menu-bar item: the same controls as the main
/// window, condensed to a fixed narrow column for at-a-glance use.
///
/// A subset of the window, not a different app: the two control groups you reach for while
/// listening (noise control, then sound) plus find-my-earbuds, which is the one thing a
/// person opens the panel *for*. The gesture editor and the About rows are configuring and
/// reading, not glancing, so they live in the window only — reachable from the "…" menu
/// here, which is also the only way to open the window while the buds are away.
struct PanelView: View {
    @Bindable var buds: Buds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    // The popover has no footer, so the header states the connection for
                    // VoiceOver here; the window's footer already does it there.
                    DeviceHeader(buds: buds, announcesConnectionState: true)
                    PowerButton(buds: buds)
                    AppMenuButton()
                }

                if buds.isConnected {
                    BatteryChipsRow(buds: buds)
                    NoiseControlSection(buds: buds)
                    SoundSection(buds: buds)
                    FindMyEarbudsSection(buds: buds)
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: buds.isConnected)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28),
                   value: buds.battery.enclosure == nil)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: buds.battery.left)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: buds.battery.right)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: buds.placement.left)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: buds.placement.right)
    }
}
