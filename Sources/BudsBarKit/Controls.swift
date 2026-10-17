import AppKit
import SwiftUI

// The controls shared by the two surfaces the app offers: the menu-bar popover
// (compact, at-a-glance) and the main window (roomy, resizable). They render the same
// live `Buds` state, so only the arrangement differs — the pieces live here and each
// surface decides how to lay them out.

// MARK: - Status

/// Small "live" dot used next to the device name.
struct StatusDot: View {
    var on: Bool

    var body: some View {
        Circle()
            .fill(on ? Theme.green : Color.white.opacity(0.25))
            .frame(width: 8, height: 8)
            .shadow(color: on ? Theme.green.opacity(0.8) : .clear, radius: 5)
    }
}

/// The round power control in the top corner. Filled with the accent while the buds are
/// connected, hairline-outlined while they are not — the same toggle in both surfaces.
struct PowerButton: View {
    @Bindable var buds: Buds

    var body: some View {
        let on = buds.isConnected
        Button {
            if on { buds.disconnect() } else { buds.connect() }
        } label: {
            ZStack {
                Circle().fill(on ? Theme.accent : Color.white.opacity(0.08))
                Circle().stroke(Color.white.opacity(on ? 0.35 : 0.14), lineWidth: 1)
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.secondary))
            }
            .frame(width: 44, height: 44)
            .shadow(color: on ? Theme.accent.opacity(0.55) : .clear, radius: 14)
        }
        .buttonStyle(.plain)
        .disabled(buds.isBusy || !buds.isPaired)
        .opacity(buds.isBusy || !buds.isPaired ? 0.5 : 1)
        .help(on ? "Disconnect" : "Connect")
        .accessibilityLabel(on ? "Disconnect earbuds" : "Connect earbuds")
    }
}

/// "Earbuds · <name> ●" with the chip glyph, mirroring the reference's "Room 27°C ●".
struct DeviceHeader: View {
    @Bindable var buds: Buds

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "airpods.gen3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.chip))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("Earbuds")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                HStack(spacing: 6) {
                    Text(buds.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    StatusDot(on: buds.isConnected)
                }
            }
            Spacer(minLength: 6)
        }
    }
}

// MARK: - Battery

/// One battery stat: glyph + label, a bold reading, and a thin level bar. Dimmed when
/// the bud is stowed in the case or its level is unknown.
struct BatteryChip: View {
    var title: String
    var glyph: String
    var level: Int?
    var placement: BudsProtocol.BudPlacement? = nil

    var body: some View {
        let stowed = placement == .inCase
        let muted = stowed || level == nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.secondary)

            // No unit without a reading: "—%" renders the dash and the percent as two
            // unrelated marks, and the dash alone already says "unknown".
            Text(level.map { "\($0)%" } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(muted ? AnyShapeStyle(Theme.secondary) : AnyShapeStyle(.white))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(muted ? Color.white.opacity(0.25) : Theme.accent)
                        .frame(width: geo.size.width * CGFloat(level ?? 0) / 100)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            level.map { "\(title) battery \($0) percent\(stowed ? ", in the case" : "")" }
                 ?? "\(title) battery unknown")
    }
}

/// Left / right / (case, when it reports) as one row of equal chips.
struct BatteryChipsRow: View {
    @Bindable var buds: Buds

    var body: some View {
        HStack(spacing: 10) {
            BatteryChip(title: "Left", glyph: "airpods.gen3", level: buds.battery.left,
                        placement: buds.placement.left)
            BatteryChip(title: "Right", glyph: "airpods.gen3", level: buds.battery.right,
                        placement: buds.placement.right)
            // The case reports 0% while it is shut or asleep, which `interpret` turns into
            // nil rather than a false flat battery — that already drops the chip on its own.
            if buds.battery.enclosure != nil {
                BatteryChip(title: "Case", glyph: "airpods.pro.chargingcase.wireless.fill",
                            level: buds.battery.enclosure)
            }
        }
    }
}

// MARK: - Hero

/// Faint concentric arcs below the device pill — the "airflow" motif from the reference,
/// read here as sound leaving the buds. Purely decorative.
struct SoundWaves: View {
    var count: Int = 4

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let diameter = CGFloat(64 + i * 26)
                Circle()
                    .trim(from: 0.06, to: 0.44)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.accent.opacity(fade(i)), .clear],
                            startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: diameter, height: diameter)
            }
        }
        .allowsHitTesting(false)
    }

    private func fade(_ index: Int) -> Double { max(0.06, 0.45 - Double(index) * 0.08) }
}

/// The wide device pill, the analogue of the reference's wall unit: a light glyph, a
/// label, and the reading, on a frosted capsule.
struct DevicePill: View {
    var glyph: String
    var title: String
    var level: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 214)
        .premiumCard(cornerRadius: 18)
    }
}

/// The headline: the case pill, sound waves, and the number that matters — the weaker
/// earbud's charge, which is when you actually need to reach for the case.
struct BatteryHero: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(spacing: 4) {
            DevicePill(glyph: "airpods.pro.chargingcase.wireless.fill",
                       title: "Charging case", level: buds.battery.enclosure)

            // Sound leaving the buds, standing in for the reference's airflow. Clipped so
            // the arcs fade out instead of running down into the reading below.
            SoundWaves(count: 4)
                .frame(height: 78)
                .clipped()

            headlineView
                .padding(.top, 2)

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// The lower of the two buds — the one you'd need to charge first.
    private var weakest: Int? {
        [buds.battery.left, buds.battery.right].compactMap { $0 }.min()
    }

    /// A known reading lays the number and its unit out on their shared baseline, which is
    /// what a big figure with a small unit wants. An unknown one is a dimmed dash, small
    /// enough to read as a placeholder rather than a ruled line across the panel — which
    /// is what a 68pt em dash looks like, and it drags the `%` down with it.
    @ViewBuilder
    private var headlineView: some View {
        if let weakest {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(weakest)")
                    .font(.system(size: 68, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.secondary)
            }
        } else {
            Text("—")
                .font(.system(size: 46, weight: .light, design: .rounded))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var caption: String {
        weakest == nil ? "Battery unknown" : "Lowest earbud"
    }

    private var accessibilityText: String {
        weakest.map { "Lowest earbud battery \($0) percent" } ?? "Earbud battery unknown"
    }
}

// MARK: - Noise control

/// The four modes as equal pills: glyph on top, label below, accent-filled when active.
///
/// Four across rather than the three this started with, because Adaptive is a real fourth
/// mode and not a variant of cancellation — the phone shows it as a peer of the others, and
/// leaving it out meant the one mode that adapts by itself was unreachable.
struct ModeGrid: View {
    @Bindable var buds: Buds

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NoiseMode.allCases) { mode in
                pill(mode)
            }
        }
    }

    private func pill(_ mode: NoiseMode) -> some View {
        let selected = buds.mode == mode
        return Button {
            buds.set(mode: mode)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 20, weight: .medium))
                // Two lines, reserved, because "Noise cancellation" does not fit one on a
                // 76pt pill and truncating it to "Noise canc…" looks like a bug.
                Text(mode.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.92)))
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.92) : Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.32) : Theme.cardStroke, lineWidth: 1))
            .shadow(color: selected ? Theme.accent.opacity(0.45) : .clear, radius: 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The strength of cancellation, shown only while Noise cancellation is the active mode.
/// Four capsules, the same four the phone offers.
struct LevelSelector: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Level")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                Text(buds.ancLevel?.label ?? "—")
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 8) {
                ForEach(ANCLevel.allCases) { level in
                    segment(level)
                }
            }

            Text(buds.ancLevel?.detail ?? "Waiting for the buds to report a level")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func segment(_ level: ANCLevel) -> some View {
        let selected = buds.ancLevel == level
        return Button {
            buds.set(ancLevel: level)
        } label: {
            Text(level.label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.secondary))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    Capsule().fill(selected ? Theme.accent.opacity(0.9) : Color.white.opacity(0.07)))
                .overlay(
                    Capsule().stroke(selected ? Color.white.opacity(0.30) : Theme.cardStroke,
                                     lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Heading, help, the mode pills, and the level picker when it applies.
struct NoiseControlSection: View {
    @Bindable var buds: Buds
    @State private var showingHelp = false

    private var canSwitchModes: Bool { buds.isControlChannelOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Noise control")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showingHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    Text("Noise cancellation blocks outside sound, at whichever level "
                       + "you pick — High for planes and trains, Low for home. Adaptive "
                       + "switches between cancelling and letting sound in as your "
                       + "surroundings change. Transparency lets sound through so you can "
                       + "hear around you. Off does neither.")
                        .font(.callout)
                        .frame(width: 260)
                        .padding(12)
                }
            }

            ModeGrid(buds: buds)
                .disabled(!canSwitchModes)
                .opacity(canSwitchModes ? 1 : 0.5)

            if buds.mode == .noiseCancellation {
                LevelSelector(buds: buds)
                    .disabled(!canSwitchModes)
                    .opacity(canSwitchModes ? 1 : 0.5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !canSwitchModes {
                Text("Waiting for the control channel…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .animation(.smooth(duration: 0.25), value: buds.mode)
        .animation(.smooth(duration: 0.25), value: buds.isControlChannelOpen)
    }
}

// MARK: - Sound

/// Sound Master EQ. The three presets the firmware ships, plus the custom slot — offered only
/// once the buds actually hold a profile, because selecting an empty one leaves the phone's own
/// screen with nothing ticked.
struct EQPresetSelector: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Sound Master EQ")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                Text(buds.eqPreset?.label ?? "—")
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 8) {
                ForEach(EQPreset.allCases) { preset in
                    segment(preset)
                }
            }
        }
    }

    private func segment(_ preset: EQPreset) -> some View {
        let available = preset != .custom || buds.hasCustomEQProfile
        let selected = buds.eqPreset == preset
        return Button {
            buds.set(eqPreset: preset)
        } label: {
            Text(preset.label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.secondary))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.accent.opacity(0.9) : Color.white.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Color.white.opacity(0.30) : Theme.cardStroke,
                                lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .help(available ? preset.label : "Save a custom profile in the phone app first")
        .accessibilityLabel(preset.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// BassWave: the bass emphasis, one step at a time from −5 to +5.
///
/// Eleven tappable ticks rather than a slider. The reference hardware's own range is five
/// either side of flat, so the whole scale fits on screen at once — which a slider would only
/// hide behind a drag — and a plain `Slider` is an AppKit control the README's screenshots
/// cannot rasterise.
struct BassWaveControl: View {
    @Bindable var buds: Buds

    private static let range = -5...5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("BassWave")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                Text(levelText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 4) {
                ForEach(Array(Self.range), id: \.self) { value in
                    tick(value)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("BassWave level")
    }

    /// Signed at both ends: "5" for a bass boost reads as a level, "+5" reads as a boost.
    private var levelText: String {
        guard let level = buds.bassWave else { return "—" }
        if level > 0 { return "+\(level)" }
        return "\(level)"
    }

    private func tick(_ value: Int) -> some View {
        let selected = buds.bassWave == value
        // The centre gets a brighter resting fill so flat reads as flat even when the buds
        // have not answered yet and nothing is selected.
        let resting = value == 0 ? 0.16 : 0.08
        return Button {
            buds.set(bassWave: value)
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.9) : Color.white.opacity(resting))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selected ? Color.white.opacity(0.30) : Theme.cardStroke,
                                lineWidth: 1))
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value > 0 ? "Bass plus \(value)" : "Bass \(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The audio effects the buds implement themselves: the EQ preset and BassWave. The phone's
/// third row here, Golden Sound, is a hearing test that writes a calibration table this app
/// does not decode; 3D Audio is processed on the phone, not the buds.
struct SoundSection: View {
    @Bindable var buds: Buds

    private var enabled: Bool { buds.isControlChannelOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sound")
                .font(.system(size: 15, weight: .semibold))

            EQPresetSelector(buds: buds)
            BassWaveControl(buds: buds)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Find my earbuds

/// Rings a bud so it can be found. The tone stops itself, and there is no opcode to stop it
/// early, so nothing here offers a cancel that could not be honoured.
struct FindMyEarbudsSection: View {
    @Bindable var buds: Buds

    private var enabled: Bool { buds.isControlChannelOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find my earbuds")
                .font(.system(size: 15, weight: .semibold))

            Text("Plays a tone in the earbuds. It stops on its own.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)

            HStack(spacing: 8) {
                ringButton("Left", slots: [.left])
                ringButton("Right", slots: [.right])
                ringButton("Both", slots: [.left, .right])
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private func ringButton(_ title: String, slots: [BudsProtocol.BatterySlot]) -> some View {
        Button {
            buds.find(slots)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play a tone in the \(title) earbud")
    }
}

// MARK: - Earbud controls

/// The touch-gesture table, one row per gesture.
///
/// Only the media context and only the four gestures the phone's own screen offers. The
/// in-call context is left alone deliberately: its codes are undocumented, and writing a
/// guess could rebind the gesture that ends a call.
struct EarbudControlsSection: View {
    @Bindable var buds: Buds

    private var enabled: Bool { buds.isControlChannelOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earbud controls")
                .font(.system(size: 15, weight: .semibold))

            Text("What each touch gesture does. Both earbuds are changed together.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)

            VStack(spacing: 6) {
                ForEach(BudsProtocol.MediaGesture.allCases) { gesture in
                    GestureRow(buds: buds, gesture: gesture)
                }
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// One gesture: what it does now, and a menu to re-point it. The menu offers only the actions
/// the phone offers for that gesture, since the firmware itself validates nothing.
struct GestureRow: View {
    @Bindable var buds: Buds
    var gesture: BudsProtocol.MediaGesture

    private var current: BudsProtocol.GestureAction? {
        buds.touchAction(gesture)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: gesture.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))

            Text(gesture.label)
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 6)

            Menu {
                Picker("", selection: Binding(
                    get: { current ?? .none },
                    set: { buds.setTouch(gesture: gesture, action: $0) }
                )) {
                    ForEach(gesture.actions) { action in
                        Label(action.label, systemImage: action.symbol).tag(action)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(current?.label ?? "Unknown")
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.5)
                }
                .foregroundStyle(current == nil ? AnyShapeStyle(Theme.secondary)
                                                : AnyShapeStyle(.white.opacity(0.92)))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("\(gesture.label) action")
            .accessibilityValue(current?.label ?? "Unknown")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 14)
    }
}

// MARK: - About

/// Read-only facts about the buds themselves, as the phone's "About" screen shows them.
struct DeviceDetailsSection: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About the earbuds")
                .font(.system(size: 15, weight: .semibold))

            row("Firmware", buds.firmware ?? "—", monospaced: true)
            row("Custom EQ profile", buds.hasCustomEQProfile ? "Saved" : "None")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 16)
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium,
                              design: monospaced ? .monospaced : .default))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Empty state

/// Shown instead of the controls when the buds are not connected. Says which of the two
/// situations it is — unpaired, or merely disconnected — since the fix differs.
struct BudsDisconnectedNote: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: buds.isPaired ? "earbuds.case" : "questionmark.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.9))
                .padding(.bottom, 2)

            Text(buds.isPaired ? "Earbuds are away" : "No earbuds paired")
                .font(.system(size: 15, weight: .semibold))

            Text(buds.isPaired
                 ? "Take the earbuds out of the case, then switch on to connect."
                 : "No paired earbuds speak this protocol. Pair your OnePlus Buds 4 in "
                 + "Bluetooth settings first.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 20)
    }
}

// MARK: - Menu

/// The "…" menu. Offering the window here means the app is reachable from the status
/// item even while the buds are away and the window is closed.
struct AppMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Button("Open \(AppInfo.name)") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppInfo.mainWindowID)
            }
            Divider()
            Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }
}
