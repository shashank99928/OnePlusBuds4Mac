import SwiftUI

/// The roomy, resizable window: the same live state as the menu-bar popover, laid out
/// for a full window — a device header with the power control, a battery hero, the
/// per-slot chips, and the noise-control pills.
struct MainWindowView: View {
    @Bindable var buds: Buds

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        topBar

                        if buds.isConnected {
                            BatteryHero(buds: buds)
                            BatteryChipsRow(buds: buds)
                            NoiseControlSection(buds: buds)
                        } else {
                            BudsDisconnectedNote(buds: buds)
                        }

                        if let error = buds.lastError {
                            errorRow(error)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.hidden)

                footer
            }
        }
        .frame(minWidth: 420, minHeight: 460)
        .premiumSurface()
        .onAppear { buds.refreshConnectionState() }
        .animation(.smooth(duration: 0.28), value: buds.isConnected)
        .animation(.smooth(duration: 0.28), value: buds.battery.enclosure == nil)
        .animation(.smooth(duration: 0.28), value: buds.battery.left)
        .animation(.smooth(duration: 0.28), value: buds.battery.right)
        .animation(.smooth(duration: 0.28), value: buds.placement.left)
        .animation(.smooth(duration: 0.28), value: buds.placement.right)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            DeviceHeader(buds: buds)
            PowerButton(buds: buds)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            StatusDot(on: buds.isConnected)
            Text(statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            AppMenuButton()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.cardStroke).frame(height: 1)
                }
        )
    }

    private var statusLine: String {
        let state = buds.isPaired
            ? (buds.isConnected ? "Connected" : "Disconnected")
            : "Not paired"
        return "\(state) · \(AppInfo.name) \(AppInfo.version)"
    }

    // MARK: - Error

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 14)
    }
}
