import AppKit
import SwiftUI

// The controls shared by the two surfaces the app offers: the menu-bar popover
// (compact, at-a-glance) and the main window (roomy, resizable). They render the same
// live `Buds` state, so only the arrangement differs — the pieces live here and each
// surface decides how to lay them out.

// MARK: - Status

/// Small "live" dot used next to the device name.
///
/// Decorative: the connection state is carried by text instead — the window's footer says
/// "Connected" / "Disconnected", and in the popover (which has no footer) `DeviceHeader`
/// announces it for VoiceOver — so a screen reader hearing a colourless dot as well would
/// only be noise.
struct StatusDot: View {
    var on: Bool

    var body: some View {
        Circle()
            .fill(on ? Theme.green : Color.white.opacity(0.25))
            .frame(width: 8, height: 8)
            .shadow(color: on ? Theme.green.opacity(0.8) : .clear, radius: 5)
            .accessibilityHidden(true)
    }
}

/// The one-line explanation shown under a section whose controls cannot be used yet.
///
/// Deliberately not a blanket `.opacity(0.5)` over the section. Halving the opacity halved
/// the *selected* control too, so the one piece of state a user is trying to confirm became
/// the hardest thing on screen to read — and it conflated "not ready for another second"
/// with "not available". A selected control now stays at full strength, the inactive ones
/// recede a little, and this says why.
struct ControlsNotReady: View {
    var text: String

    /// The two reasons a section can be waiting want different words, and only one is "reading".
    ///
    /// A read that has not landed yet has nothing to show. A closed control channel is reading
    /// nothing at all, and the section is holding its last readings — the channel dropped while the
    /// audio link stayed up. Saying "Reading…" there would be untrue about what the app is doing,
    /// over exactly the values most likely to be mistaken for current.
    static func wording(_ reading: String, channelOpen: Bool, hasReading: Bool) -> String {
        (!channelOpen && hasReading) ? "Reconnecting to the earbuds…" : reading
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// How far an *inactive* control recedes while the control channel is still opening.
///
/// The selected control is exempt — see `ControlsNotReady` — which is the whole reason this
/// is applied per control rather than to the section.
func channelDim(_ enabled: Bool, selected: Bool = false) -> Double {
    enabled || selected ? 1 : 0.55
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
                Circle().fill(on ? Theme.selection : Color.white.opacity(0.08))
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
        // A constant label with the state as a value, rather than a label that flips between
        // two actions: a disabled button that still reads "Connect earbuds" announces an
        // action it cannot perform.
        .accessibilityLabel("Earbuds power")
        .accessibilityValue(on ? "Connected" : "Disconnected")
    }
}

/// "Earbuds · <name> ●" with the chip glyph, mirroring the reference's "Room 27°C ●".
struct DeviceHeader: View {
    @Bindable var buds: Buds
    /// The window's footer already announces the connection state, so it is off there. The
    /// popover has no footer, so its header carries the state for VoiceOver instead.
    var announcesConnectionState = false

    var body: some View {
        if announcesConnectionState {
            header
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Earbuds, \(buds.name)")
                .accessibilityValue(connectionState)
        } else {
            header
        }
    }

    /// The same phrase the window's footer uses, so the two surfaces say the same thing.
    private var connectionState: String {
        buds.isPaired ? (buds.isConnected ? "Connected" : "Disconnected") : "Not paired"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.chip))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1))
                .accessibilityHidden(true)

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
        // A bud that is in the case, or that has gone absent, is not in use: it must not be
        // drawn at full strength nor its last reading presented as current. `notPresent` is
        // decodable but was never seen on hardware, so it is folded in with `inCase`.
        let stowed = !(placement?.isUsable ?? true)
        let muted = stowed || level == nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityHidden(true)
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
            level.map { "\(title) battery \($0) percent\(stowed ? ", not in use" : "")" }
                 ?? "\(title) battery unknown")
    }
}

/// Left / right / (case, when it reports) as one row of equal chips.
struct BatteryChipsRow: View {
    @Bindable var buds: Buds

    /// Nothing has been read yet: the channel is not open and neither bud has a level. The
    /// chips would be bare dashes with nothing to explain them — the state the warming-up
    /// panel exists to avoid — so the row says why instead.
    private var isWaitingForBattery: Bool {
        buds.battery.left == nil && buds.battery.right == nil && !buds.isControlChannelOpen
    }

    /// The case is known to be there, a bud has been read, and the case's own charge has still
    /// not arrived — the steady state whenever the buds are out of it.
    private var isCaseChargeUnreported: Bool {
        buds.isCaseReported && buds.battery.enclosure == nil
            && buds.isControlChannelOpen
            && (buds.battery.left != nil || buds.battery.right != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BatteryChip(title: "Left", glyph: "earbud.left", level: buds.battery.left,
                            placement: buds.placement.left)
                BatteryChip(title: "Right", glyph: "earbud.right", level: buds.battery.right,
                            placement: buds.placement.right)
                // The case reports 0% while it is shut or asleep, which `interpret` turns into
                // nil rather than a false flat battery — that already drops the chip on its own.
                // Its *presence* is separate from its charge: the wear report names the slot
                // whenever the case is awake, and the hero uses the same evidence, so the two
                // surfaces agree instead of one inventing a case and the other hiding it.
                if buds.isCaseReported {
                    BatteryChip(title: "Case", glyph: "earbuds.case.fill",
                                level: buds.battery.enclosure)
                }
            }

            if isWaitingForBattery {
                ControlsNotReady(text: "Reading the battery…")
            }

            // The case names itself in the wear report but never in the battery report — 60 of
            // 60 replies in one session carried left and right only — so its chip sits at a
            // permanent dash. A dash means "no reading", which is true, but on its own it reads
            // as a value that failed to load. One sentence says which unknown this is.
            if isCaseChargeUnreported {
                Text("The case hasn't reported its charge.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                // A dash here read as a number that had not arrived yet. For the case it never
                // arrives — the buds report left and right only — so the pill says which
                // unknown this is instead of drawing a value-shaped hole.
                Text(level.map { "\($0)%" } ?? "Not reported")
                    .font(.system(size: level == nil ? 13 : 17,
                                  weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 214)
        .premiumCard(cornerRadius: 16)
    }
}

/// The headline: the case pill, sound waves, and the number that matters — the weaker
/// earbud's charge, which is when you actually need to reach for the case.
struct BatteryHero: View {
    @Bindable var buds: Buds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            // The case is only drawn once something has reported it — the wear report names
            // the slot whenever the case is awake, the battery report names it when its charge
            // is read. Without either, a permanent "Case —" claimed a case the buds had never
            // mentioned, and disagreed with the panel, which omitted it.
            if buds.isCaseReported {
                DevicePill(glyph: "earbuds.case.fill",
                           title: "Case", level: buds.battery.enclosure)
            }

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
        // `.combine` would gather the children and then be overridden by the label below,
        // which dropped the case reading entirely — the pill is inside this subtree and its
        // own value never reached the reader. The label is built from the same state the
        // children show, so nothing is lost by describing it once.
        .accessibilityElement(children: .ignore)
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
                    .contentTransition(reduceMotion ? .identity : .numericText())
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
        weakest == nil ? "Battery unknown" : "Lowest earbud charge"
    }

    private var accessibilityText: String {
        let lowest = weakest.map { "Lowest earbud battery \($0) percent" }
            ?? "Earbud battery unknown"
        if let enclosure = buds.battery.enclosure {
            return "\(lowest). Case battery \(enclosure) percent"
        }
        // The pill says "Not reported" in this state, so the spoken summary says it too
        // rather than dropping the case — a reader that hears only the buds cannot tell
        // whether the case is absent or simply unread.
        guard buds.isCaseReported else { return lowest }
        return "\(lowest). Case battery not reported"
    }
}

// MARK: - Noise control

/// The four modes as equal pills: glyph on top, label below, filled when active.
///
/// Four across rather than the three this started with, because Adaptive is a real fourth
/// mode and not a variant of cancellation — the phone shows it as a peer of the others, and
/// leaving it out meant the one mode that adapts by itself was unreachable.
///
/// Four across is also the phone's own layout, and it is what the window gets. It does not
/// fit a 308pt panel, nor the window at its minimum width: "Noise cancellation" needs about
/// 62pt at the 0.7 scale floor, and four pills in those widths leave 41.5pt and 58.5pt of
/// inner width, so the label clipped to "cancell…". Two across leaves 121pt, which is room
/// to spare, so the narrow case falls back to a 2×2 grid rather than truncating.
struct ModeGrid: View {
    @Bindable var buds: Buds

    private static let spacing: CGFloat = 10

    /// The container width at which four pills leave enough room for the longest label.
    /// Measured, then rounded up for headroom — there are no font metrics at compile time,
    /// so `SnapshotTests` pins both branches against the two real surface widths.
    static let fourAcrossMinimum: CGFloat = 400

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Self.spacing) {
                ForEach(NoiseMode.allCases) { pill($0) }
            }
            .frame(minWidth: Self.fourAcrossMinimum)

            // A plain `Grid`, not `LazyVGrid`: a lazy container has nothing to lay out when
            // the whole thing is drawn offscreen, which is exactly how the golden images and
            // the README screenshots are produced.
            Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
                GridRow { pill(.noiseCancellation); pill(.adaptive) }
                GridRow { pill(.transparency); pill(.off) }
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
                    .accessibilityHidden(true)
                // Two lines, reserved, because "Noise cancellation" does not fit one line on
                // a narrow pill and truncating it to "Noise canc…" looks like a bug.
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.selection : Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Theme.selectionStroke : Theme.cardStroke, lineWidth: 1))
            .shadow(color: selected ? Theme.accent.opacity(0.45) : .clear, radius: 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(channelDim(buds.isControlChannelOpen, selected: selected))
        .accessibilityLabel(mode.label)
        .accessibilityValue(selected ? "Selected" : "Not selected")
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

            // A dash above and this line below, rather than a sentence that repeats what the
            // dashes already say. The states are: known (the word and its detail), not yet
            // reported, and the levels genuinely do not apply outside Noise cancellation.
            Text(buds.ancLevel?.detail ?? "Level not reported yet")
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
                    Capsule().fill(selected ? Theme.selection : Color.white.opacity(0.07)))
                .overlay(
                    Capsule().stroke(selected ? Theme.selectionStroke : Theme.cardStroke,
                                     lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .opacity(channelDim(buds.isControlChannelOpen, selected: selected))
        .accessibilityLabel(level.label)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Heading, help, the mode pills, and the level picker when it applies.
struct NoiseControlSection: View {
    @Bindable var buds: Buds
    @State private var showingHelp = false

    /// Enabled only once the current mode has been read: with no readback the pills have
    /// nothing to mark as selected, so an enabled grid of unselected pills would claim the
    /// buds are on no mode at all. The notice below says why in the meantime.
    private var canSwitchModes: Bool { buds.isControlChannelOpen && buds.mode != nil }

    /// Honor the system setting: the level row slides in and out, and the pills cross-fade
    /// when the mode changes. Both are decoration, and both are the kind that makes some
    /// people motion-sick.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .accessibilityLabel("About noise control")
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

            // No blanket opacity over the group: `ModeGrid` recedes its own inactive pills
            // and keeps the selected one at full strength. See `ControlsNotReady`.
            ModeGrid(buds: buds)
                .disabled(!canSwitchModes)

            if buds.mode == .noiseCancellation {
                LevelSelector(buds: buds)
                    .disabled(!canSwitchModes)
                    .transition(reduceMotion ? .identity
                                             : .opacity.combined(with: .move(edge: .top)))
            }

            if !canSwitchModes {
                ControlsNotReady(text: ControlsNotReady.wording(
                    "Reading the noise-control setting…",
                    channelOpen: buds.isControlChannelOpen, hasReading: buds.mode != nil))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: buds.mode)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: buds.isControlChannelOpen)
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
        let available = preset != .custom || buds.hasCustomEQProfile == true
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
                        .fill(selected ? Theme.selection : Color.white.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Theme.selectionStroke : Theme.cardStroke,
                                lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        // A segment that is selected but not available — the buds are on the custom preset
        // while its profile has been deleted on the phone — keeps its selected styling.
        // Greying it out would hide the one piece of state the row exists to report.
        .opacity(available ? channelDim(buds.isControlChannelOpen, selected: selected)
                           : (selected ? 1 : 0.45))
        .help(available ? preset.label : "Save a custom profile in the phone app first")
        .accessibilityLabel(preset.label)
        // The reason Custom is unusable is not visible on screen — the tone of its label is
        // the only cue — so it is stated instead of left to be inferred from being greyed out.
        .accessibilityHint(available ? "" : "Save a custom profile in the phone app first")
        .accessibilityValue(selected ? "Selected" : "Not selected")
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
        // One adjustable element instead of eleven buttons. Eleven 24pt tab stops told a
        // VoiceOver user nothing but a number each, and the only thing separating one from
        // another was its fill colour — which is exactly the cue that does not exist for
        // someone who cannot see it. The ticks stay for the pointer; the accessibility tree
        // gets the whole scale at once.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BassWave")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Swipe up or down to change the bass emphasis")
        .accessibilityAdjustableAction { direction in
            // Without a reading there is no level to step from. Inventing flat (0) would send
            // the real level ± 1, and this control's whole value is that it edits the value it
            // announces — which, unread, is "Not reported".
            guard let current = buds.bassWave else { return }
            switch direction {
            case .increment: buds.set(bassWave: min(current + 1, Self.range.upperBound))
            case .decrement: buds.set(bassWave: max(current - 1, Self.range.lowerBound))
            @unknown default: break
            }
        }
    }

    /// Signed at both ends: "5" for a bass boost reads as a level, "+5" reads as a boost.
    private var levelText: String {
        guard let level = buds.bassWave else { return "—" }
        if level > 0 { return "+\(level)" }
        return "\(level)"
    }

    private var accessibilityValue: String {
        guard let level = buds.bassWave else { return "Not reported" }
        if level == 0 { return "Flat" }
        return level > 0 ? "Plus \(level) of 5" : "Minus \(-level) of 5"
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
                .fill(selected ? Theme.selection : Color.white.opacity(resting))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selected ? Theme.selectionStroke : Theme.cardStroke,
                                lineWidth: 1))
                // Height as well as colour: the selected step stands proud of the row, so the
                // current level is legible in a greyscale screenshot and to anyone who does
                // not separate blue from grey.
                .frame(height: selected ? 30 : 24)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(channelDim(buds.isControlChannelOpen, selected: selected))
        .accessibilityHidden(true)
    }
}

/// The audio effects the buds implement themselves: the EQ preset and BassWave. The phone's
/// third row here, Golden Sound, is a hearing test that writes a calibration table this app
/// does not decode; 3D Audio is processed on the phone, not the buds.
struct SoundSection: View {
    @Bindable var buds: Buds

    /// The EQ preset and BassWave are both read once when the channel opens; the section waits
    /// for both, so neither control is enabled while its value is still unknown — and a read
    /// that was lost leaves the notice up rather than an enabled row showing "—".
    private var isReady: Bool {
        buds.isControlChannelOpen && buds.eqPreset != nil && buds.bassWave != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sound")
                .font(.system(size: 15, weight: .semibold))

            EQPresetSelector(buds: buds)
            BassWaveControl(buds: buds)

            if !isReady {
                ControlsNotReady(text: ControlsNotReady.wording(
                    "Reading the sound settings…",
                    channelOpen: buds.isControlChannelOpen,
                    hasReading: buds.eqPreset != nil || buds.bassWave != nil))
            }
        }
        .disabled(!isReady)
    }
}

// MARK: - Find my earbuds

/// Rings a bud so it can be found. The tone stops itself, and there is no opcode to stop it
/// early, so nothing here offers a cancel that could not be honoured.
struct FindMyEarbudsSection: View {
    @Bindable var buds: Buds

    private var enabled: Bool { buds.isControlChannelOpen }

    /// True when the wear report says both buds are stowed.
    ///
    /// The vendor's app refuses to start a tone in exactly this state (`EarStatusDTO.bothInBox()`
    /// gates its find screen), and the reason is physical: the tone comes from a bud, and a bud in
    /// the case is charging. The buttons stay live — what the firmware will do is the firmware's
    /// decision — but the likeliest reason for a tap that does nothing gets said out loud.
    private var bothStowed: Bool {
        buds.placement.left?.isStowed == true && buds.placement.right?.isStowed == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find my earbuds")
                .font(.system(size: 15, weight: .semibold))

            // Stop is the vendor's own exit-find frame, byte for byte — but the firmware answers
            // every find request identically, so no trace shows a tone starting or stopping. The
            // sentence says the earbuds are *asked* rather than promising silence.
            Text("Plays a tone in the earbuds. Stop asks them to end it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)

            if bothStowed {
                Text("Both earbuds are in the case — the phone app won't start a tone "
                    + "until one comes out.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 8) {
                findButton("Left", glyph: "speaker.wave.2.fill",
                           spoken: "Play a tone in the left earbud") { buds.find([.left]) }
                findButton("Right", glyph: "speaker.wave.2.fill",
                           spoken: "Play a tone in the right earbud") { buds.find([.right]) }
                findButton("Both", glyph: "speaker.wave.2.fill",
                           spoken: "Play a tone in both earbuds") { buds.find([.left, .right]) }
                findButton("Stop", glyph: "speaker.slash.fill",
                           spoken: "Ask the earbuds to stop the tone") { buds.stopFind() }
            }

            if !enabled {
                ControlsNotReady(text: "Waiting for the controls to be ready…")
            }
        }
        .disabled(!enabled)
    }

    private func findButton(_ title: String, glyph: String, spoken: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
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
        .opacity(channelDim(enabled))
        // The button's own label is one word — "Both" — and the old spoken name was
        // "Play a tone in the Both earbud". The spoken name is written out in full.
        .accessibilityLabel(spoken)
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

    /// The gesture table is read once when the channel opens; until those records land there
    /// is no row to show, and an enabled row would read "Not reported" with no explanation.
    private var isReady: Bool { buds.isControlChannelOpen && !buds.touchRules.isEmpty }

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

            if !isReady {
                ControlsNotReady(text: ControlsNotReady.wording(
                    "Reading the gesture table from the earbuds…",
                    channelOpen: buds.isControlChannelOpen, hasReading: !buds.touchRules.isEmpty))
            }
        }
        .disabled(!isReady)
    }
}

/// One gesture: what it does now, and a menu to re-point it. The menu offers only the actions
/// the phone offers for that gesture, since the firmware itself validates nothing.
struct GestureRow: View {
    @Bindable var buds: Buds
    var gesture: BudsProtocol.MediaGesture

    /// `ImageRenderer` draws a coloured placeholder for a `Menu`; the snapshot renderer
    /// substitutes the bare label. See `EnvironmentValues.isRenderingSnapshot`.
    @Environment(\.isRenderingSnapshot) private var isSnapshot

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
                .accessibilityHidden(true)

            Text(gesture.label)
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 6)

            actionControl
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var actionControl: some View {
        if isSnapshot {
            actionLabel
        } else {
            Menu {
                // The selection is optional so an unread table ticks nothing: defaulting to
                // `.none` put a checkmark on "Do nothing" for a gesture that had not been
                // read. The placeholder tag is disabled, so it can be shown but not chosen;
                // the write path still carries a real action.
                Picker("", selection: Binding<BudsProtocol.GestureAction?>(
                    get: { current },
                    set: { newValue in
                        guard let newValue else { return }
                        buds.setTouch(gesture: gesture, action: newValue)
                    }
                )) {
                    Text("Not reported")
                        .tag(Optional<BudsProtocol.GestureAction>.none)
                        .disabled(true)
                    ForEach(gesture.actions) { action in
                        Label(action.label, systemImage: action.symbol)
                            .tag(Optional(action))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                actionLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("\(gesture.label) action")
            .accessibilityValue(current?.label ?? "Not reported")
        }
    }

    private var actionLabel: some View {
        HStack(spacing: 5) {
            // "Unknown" reads as a fault; the truth is that the answer has not arrived. A
            // gesture table takes a moment to be read off the buds.
            Text(current?.label ?? "Not reported")
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
}

// MARK: - About

/// Read-only facts about the buds themselves, as the phone's "About" screen shows them.
/// The phone app's "Dual connection" screen, as far as this platform can honestly take it: the
/// buds push the table of what is linked to them, and nothing here changes it. No setter for
/// connecting or disconnecting a peer has ever been seen on the wire, so the list is a reading —
/// the same treatment the About rows get — rather than buttons that would have to guess.
///
/// The row layout is the vendor SDK's own multi-connect record (six address bytes, a length
/// byte, a state byte, a flag byte, a length-prefixed name) rather than a fit to the one sample
/// this app has: read under it, that sample's two records end exactly on the body's last byte.
/// The sentence above the rows says "reports" because that is what a push is — the buds' account
/// of the link, not the Mac's.
struct LinkedDevicesSection: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Linked devices")
                .font(.system(size: 15, weight: .semibold))

            Text("What the earbuds report as linked to them.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)

            if buds.linkedDevices.isEmpty {
                // True of both ways the list can be empty: a push that has not arrived, and a
                // push that named no devices. "Waiting…" would be untrue in the second case.
                ControlsNotReady(text: "No linked devices reported.")
            }

            ForEach(buds.linkedDevices, id: \.address) { device in
                row(device)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(cornerRadius: 16)
    }

    private func row(_ device: BudsProtocol.LinkedDevice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // A device type the buds did not set draws the generic glyph rather than a laptop:
            // the type is the vendors' to state, and this capture's two entries state nothing.
            Image(systemName: device.deviceType?.symbol ?? "dot.radiowaves.left.and.right")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                // A bud can report a device it has no name for. The address is what it has
                // instead, and an empty row would read as a device that is not there.
                Text(device.name.isEmpty ? device.address : device.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(caption(device))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Says which entry is this Mac and what the buds say it is doing, and says nothing at all
    /// about a state byte the vendor numbering does not name.
    private func caption(_ device: BudsProtocol.LinkedDevice) -> String {
        var parts: [String] = []
        if device.isCurrentDevice { parts.append("this Mac") }
        switch device.state {
        case .connected?: parts.append("connected")
        case .connecting?: parts.append("connecting")
        case .disconnecting?: parts.append("disconnecting")
        case .notConnected?: parts.append("not connected")
        case nil: break
        }
        if device.isAudioActive { parts.append("playing audio") }
        else if device.isMainAudioDevice { parts.append("main audio") }
        return parts.joined(separator: " · ")
    }
}

struct DeviceDetailsSection: View {
    @Bindable var buds: Buds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About the earbuds")
                .font(.system(size: 15, weight: .semibold))

            row("Firmware", buds.firmware ?? "—", monospaced: true)
            row("Custom EQ profile",
                buds.hasCustomEQProfile.map { $0 ? "Saved" : "None" } ?? "—")
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
                .accessibilityHidden(true)

            // "Away" was the phone app's word for the buds sitting in a closed case, and it
            // reads as a place rather than a state. What is true, and what the fix follows
            // from, is that the link is down. When nothing is paired, the honest reading is
            // that the app could not find buds it can drive — which also covers a Buds 4
            // pair that is simply not connected yet, since that is what hides the service.
            Text(buds.isPaired ? "Earbuds aren't connected" : "Can't find your earbuds")
                .font(.system(size: 15, weight: .semibold))

            Text(buds.isPaired
                 ? "Take the earbuds out of the case, then switch on to connect."
                 : "If they're paired, connect them once in Bluetooth settings so macOS "
                 + "exposes the control service.")
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
    /// See `EnvironmentValues.isRenderingSnapshot`.
    @Environment(\.isRenderingSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            glyph
        } else {
            Menu {
                Button("Open \(AppInfo.name)") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: AppInfo.mainWindowID)
                }
                Divider()
                Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
            } label: {
                glyph
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }

    private var glyph: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .frame(width: 26, height: 26)
    }
}
