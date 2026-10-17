import SwiftUI

/// The roomy, resizable window: the same live state as the menu-bar popover, laid out for
/// a full window — a device header with the power control, a battery hero, the per-slot
/// chips, the noise-control pills, and the app's one preference.
struct MainWindowView: View {
    @Bindable var buds: Buds

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                ScrollView {
                    MainColumn(buds: buds)
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
}

/// The scrolling body of the window.
///
/// Split from the frame around it so it can be drawn on its own — `ImageRenderer` cannot
/// rasterise a `ScrollView`'s contents, and this is what the README screenshot renders.
struct MainColumn: View {
    @Bindable var buds: Buds
    @State private var login = LaunchAtLogin()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar

            if buds.isConnected {
                BatteryHero(buds: buds)
                BatteryChipsRow(buds: buds)
                NoiseControlSection(buds: buds)
                SoundSection(buds: buds)
                EarbudControlsSection(buds: buds)
                FindMyEarbudsSection(buds: buds)
                DeviceDetailsSection(buds: buds)
            } else {
                BudsDisconnectedNote(buds: buds)
            }

            if let error = buds.lastError {
                errorRow(error)
            }

            settingsRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            DeviceHeader(buds: buds)
            PowerButton(buds: buds)
        }
    }

    // MARK: - Settings

    /// The one app-level preference. Kept in the window rather than the popover, which is
    /// for glancing at the buds, not configuring the app.
    private var settingsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))

            VStack(alignment: .leading, spacing: 1) {
                Text("Launch at login")
                    .font(.system(size: 13, weight: .semibold))
                Text(loginSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(login.lastError == nil ? Theme.secondary : .orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Toggle("Launch at login", isOn: Binding(
                get: { login.isEnabled },
                set: { login.set($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 16)
    }

    private var loginSubtitle: String {
        if let error = login.lastError { return error }
        return login.isEnabled ? "Opens automatically when you log in"
                               : "Start the app with your Mac"
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
