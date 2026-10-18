import AppKit
import IOBluetooth
import SwiftUI
import XCTest
@testable import BudsBarKit

/// Golden images for the app's surfaces, at the widths they are actually used at.
///
/// The panel is a fixed 340pt column and the window has a minimum width, and both are exactly
/// where a layout breaks: the four noise-control pills needed 62pt each and had 41.5pt in the
/// panel, so the label clipped to "cancell…" and nothing failed. A golden image is the only
/// check that catches that class of mistake, because the wrong output is perfectly valid
/// SwiftUI — it just looks wrong.
///
/// The four site-surface goldens live in `docs/assets`, which is also the website's asset
/// directory, so the screenshot a visitor sees is byte-for-byte the one this test verifies.
/// The component goldens — the individual controls no site surface isolates — live in
/// `Tests/Goldens/`, which is test-only; `Snapshots.png(_:width:)` states why the two are
/// kept apart rather than sharing one directory.
///
/// Regenerate deliberately, and read the diff, with:
///
///     UPDATE_SNAPSHOTS=1 swift test --filter SnapshotTests
///
/// The comparison is per-pixel with a small tolerance rather than exact bytes: two macOS
/// builds can encode identical pixels differently, and a test that fails on an OS update
/// teaches people to ignore it.
@MainActor
final class SnapshotTests: XCTestCase {

    private var goldenDirectory: URL {
        URL(fileURLWithPath: #filePath)             // Tests/BudsBarKitTests/SnapshotTests.swift
            .deletingLastPathComponent()            // Tests/BudsBarKitTests
            .deletingLastPathComponent()            // Tests
            .deletingLastPathComponent()            // repository root
            .appendingPathComponent("docs/assets")
    }

    func testSurfacesMatchTheirGoldenImages() throws {
        for surface in Snapshots.Surface.allCases {
            let rendered = try XCTUnwrap(Snapshots.png(surface),
                                         "\(surface.rawValue): ImageRenderer produced nothing")
            let goldenURL = goldenDirectory.appendingPathComponent("\(surface.rawValue).png")

            if ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] != nil
                || !FileManager.default.fileExists(atPath: goldenURL.path) {
                try FileManager.default.createDirectory(at: goldenDirectory,
                                                        withIntermediateDirectories: true)
                try rendered.write(to: goldenURL)
                continue
            }

            let golden = try Data(contentsOf: goldenURL)
            let difference = try compare(rendered, golden)
            XCTAssertLessThan(
                difference.ratio, 0.005,
                """
                \(surface.rawValue) no longer matches docs/assets/\(surface.rawValue).png: \
                \(difference.pixels) of \(difference.total) pixels differ \
                (\(String(format: "%.2f", difference.ratio * 100))%). \
                If the change is intended, regenerate with UPDATE_SNAPSHOTS=1 and read the diff.
                """)
        }
    }

    /// Every surface must render at all, which is also the check that the seeded corpus
    /// actually populated the view: an empty `Buds` still draws, so a golden image alone
    /// cannot tell "the layout changed" from "there was nothing to draw".
    func testScreenshotsArePopulatedFromTheCapturedCorpus() throws {
        let buds = Buds()
        buds.seedForSnapshot()
        XCTAssertTrue(buds.isConnected)
        XCTAssertTrue(buds.isControlChannelOpen)
        XCTAssertEqual(buds.battery.left, 20, "the capture has both buds at 20%")
        XCTAssertEqual(buds.battery.right, 20)
        XCTAssertNotNil(buds.mode, "the capture has an ANC readback")
        XCTAssertNotNil(buds.eqPreset, "the capture has an EQ readback")
        XCTAssertNotNil(buds.bassWave, "the capture has a BassWave readback")
        XCTAssertNotNil(buds.firmware, "the capture has the firmware string")
        XCTAssertEqual(buds.touchRules.count, 18, "the capture has the gesture table")
    }

    // MARK: - Component goldens

    /// Where the component goldens live. Deliberately not `docs/assets`, which holds the four
    /// site surfaces — see `Snapshots.png(_:width:)` for why the two are kept apart.
    private var componentGoldenDirectory: URL {
        URL(fileURLWithPath: #filePath)             // Tests/BudsBarKitTests/SnapshotTests.swift
            .deletingLastPathComponent()            // Tests/BudsBarKitTests
            .deletingLastPathComponent()            // Tests
            .appendingPathComponent("Goldens")
    }

    /// One view pinned on its own, with the state it is pinned in written down.
    private struct ComponentGolden {
        let name: String
        /// The state, in one line, so a failure says what the picture is supposed to show.
        let state: String
        let width: CGFloat
        let view: @MainActor () -> AnyView
    }

    /// The component surfaces the four site goldens never isolate.
    ///
    /// A full-surface image proves the whole column still adds up, but a branch that only
    /// appears in a state no surface golden is taken in — Noise cancellation's level row, a
    /// case that the wear report has named but whose charge has not been read, a control
    /// channel that has dropped while its last reading is still on screen — is invisible to
    /// them. Each view here is drawn on its own, seeded from the same decoded fixture corpus
    /// (and, where a reading is readback-driven rather than settable, by replaying the
    /// capture through the real RFCOMM ingest path; see `ingest`).
    private var componentGoldens: [ComponentGolden] {
        [
            ComponentGolden(
                name: "level-selector",
                state: "Noise cancellation active at High; the nc-high capture replayed so the "
                     + "level row is in the branch that shows it",
                width: 340
            ) { [self] in
                let buds = seeded(.connected)
                ingest("anc-reply-nc-high", into: buds)
                return onDarkSurface(LevelSelector(buds: buds))
            },

            ComponentGolden(
                name: "noise-control-section-noise-cancellation",
                state: "the section with Noise cancellation active, so the level row it "
                     + "conditionally shows is present — no site golden is in this branch",
                width: 340
            ) { [self] in
                let buds = seeded(.connected)
                ingest("anc-reply-nc-high", into: buds)
                return onDarkSurface(NoiseControlSection(buds: buds))
            },

            ComponentGolden(
                name: "device-details-firmware-unknown",
                state: "nothing read yet, so the firmware row renders a dash",
                width: 470
            ) { [self] in
                // The warming-up window: connected, control channel not open, nothing read.
                onDarkSurface(DeviceDetailsSection(buds: seeded(.warmingUp)), padding: 22)
            },

            ComponentGolden(
                name: "linked-devices",
                state: "the corpus's multi-connect push replayed: this Mac, marked as the "
                     + "device the buds are talking to and connected, with the phone beside it",
                width: 470
            ) { [self] in
                let buds = seeded(.connected)
                ingest("notify-devices", into: buds)
                return onDarkSurface(LinkedDevicesSection(buds: buds), padding: 22)
            },

            ComponentGolden(
                name: "linked-devices-empty",
                state: "no table pushed yet, which is the card for the first moments after "
                     + "connecting and the state a window golden never shows",
                width: 470
            ) { [self] in
                // The corpus replays the table, so the empty branch is cleared by hand: what is
                // being pinned is the wording, and no capture holds an empty table to replay.
                let buds = seeded(.connected)
                buds.linkedDevices = []
                return onDarkSurface(LinkedDevicesSection(buds: buds), padding: 22)
            },

            ComponentGolden(
                name: "disconnected-note-paired",
                state: "paired but link down — \"Earbuds aren't connected\"",
                width: 340
            ) { [self] in
                onDarkSurface(BudsDisconnectedNote(buds: seeded(.disconnected)))
            },

            ComponentGolden(
                name: "disconnected-note-unpaired",
                state: "nothing paired — \"Can't find your earbuds\"",
                width: 340
            ) { [self] in
                // A live app with nothing paired is exactly a `Buds` that never discovered a
                // device: no seed, because seeding forces pairing.
                onDarkSurface(BudsDisconnectedNote(buds: Buds()))
            },

            ComponentGolden(
                name: "power-button-off",
                state: "off — paired, link down, so the button is outlined and enabled",
                width: 96
            ) { [self] in
                onDarkSurface(PowerButton(buds: seeded(.disconnected)), padding: 16)
            },

            ComponentGolden(
                name: "power-button-unpaired",
                state: "off with nothing paired, which is the disabled, dimmed branch",
                width: 96
            ) { [self] in
                onDarkSurface(PowerButton(buds: Buds()), padding: 16)
            },

            ComponentGolden(
                name: "status-dot-off",
                state: "the disconnected dot, driven from the seeded link state",
                width: 44
            ) { [self] in
                onDarkSurface(StatusDot(on: seeded(.disconnected).isConnected), padding: 12)
            },

            ComponentGolden(
                name: "battery-chip-case",
                state: "the case chip with the case present and its charge unread — a dash",
                width: 135
            ) { [self] in
                let buds = seeded(.connected)
                // The wear capture names the enclosure, which is the only evidence of a case;
                // the battery capture carries no case entry, so its charge reads unknown.
                return onDarkSurface(
                    BatteryChip(title: "Case", glyph: "earbuds.case.fill",
                                level: buds.battery.enclosure),
                    padding: 16)
            },

            ComponentGolden(
                name: "device-pill-case",
                state: "the hero's case pill, present with its charge unread",
                width: 260
            ) { [self] in
                let buds = seeded(.connected)
                return onDarkSurface(
                    DevicePill(glyph: "earbuds.case.fill", title: "Case",
                               level: buds.battery.enclosure),
                    padding: 16)
            },

            ComponentGolden(
                name: "basswave-flat",
                state: "flat — the 0 capture replayed so the centre tick is the selected one",
                width: 340
            ) { [self] in
                let buds = seeded(.connected)
                ingest("basswave-reply-0", into: buds)
                return onDarkSurface(BassWaveControl(buds: buds))
            },

            // The branches below were not on the audit's list. They are the same condition —
            // a real rendering branch no golden reaches — found by reading the components for
            // this change, so they are pinned too.

            ComponentGolden(
                name: "battery-hero-unknown",
                state: "no battery read: the dimmed dash headline and \"Battery unknown\"",
                width: 470
            ) { [self] in
                onDarkSurface(BatteryHero(buds: seeded(.warmingUp)), padding: 22)
            },

            ComponentGolden(
                name: "controls-not-ready-reconnecting",
                state: "a reading held while the control channel is closed — the "
                     + "\"Reconnecting to the earbuds…\" wording, not \"Reading…\"",
                width: 340
            ) { [self] in
                let buds = seeded(.connected)
                // The channel dropping while the audio link stays up: the last readings are
                // still on screen, so the notice has to say it is reconnecting rather than
                // reading. `rfcommChannelClosed` is the real teardown callback.
                buds.rfcommChannelClosed(nil)
                return onDarkSurface(ControlsNotReady(text: ControlsNotReady.wording(
                    "Reading the noise-control setting…",
                    channelOpen: buds.isControlChannelOpen,
                    hasReading: buds.mode != nil)))
            },

            ComponentGolden(
                name: "earbud-controls-warming",
                state: "before the gesture table is read: every row says \"Not reported\"",
                width: 470
            ) { [self] in
                onDarkSurface(EarbudControlsSection(buds: seeded(.warmingUp)), padding: 22)
            },

            // The connect popup. It is on screen for a couple of seconds and is the surface
            // least likely to be looked at by hand, so the branch that can clip — a sentence
            // inside a capsule, or a third cell appearing when the case reports a charge — is
            // pinned rather than trusted.
            ComponentGolden(
                name: "floating-battery-connected",
                state: "the popup with both readings in: L, R and no case cell, because the "
                     + "battery capture carries no case entry",
                width: 320
            ) { [self] in
                onDarkSurface(FloatingBatteryView(buds: seeded(.connected)), padding: 20)
            },

            ComponentGolden(
                name: "floating-battery-waiting",
                state: "the popup in the instant it opens: link up, nothing read, so "
                     + "\"Reading the battery…\" instead of two dashes",
                width: 320
            ) { [self] in
                onDarkSurface(FloatingBatteryView(buds: seeded(.warmingUp)), padding: 20)
            },
        ]
    }

    /// Seeds a `Buds` the way `Surface.image` does, so a component shows the same state a
    /// surface golden does rather than a different one invented beside it.
    private func seeded(_ state: Buds.SnapshotState = .connected) -> Buds {
        let buds = Buds()
        buds.seedForSnapshot(state)
        return buds
    }

    /// Replays one captured corpus frame through the real RFCOMM ingest path — the delegate
    /// callback the radio itself calls — to reach a reading the setters cannot.
    ///
    /// `set(mode:)`, `set(ancLevel:)`, `set(eqPreset:)` and `set(bassWave:)` command the buds
    /// and deliberately leave the model alone: the UI renders what was *read back*, so a
    /// setter with no channel behind it moves nothing. Replaying a capture is therefore the
    /// only honest way to put a readback-driven reading where the hardware reported it — and
    /// it is the same operation `seedForSnapshot` performs, just with an individual frame. No
    /// frame is ever synthesized: if the reading was not captured, the state stays unpinned.
    private func ingest(_ captureName: String, into buds: Buds) {
        guard let capture = FixtureCorpus.frames.first(where: { $0.name == captureName }) else {
            return XCTFail("no capture named \(captureName) in the corpus")
        }
        var bytes = capture.bytes
        bytes.withUnsafeMutableBytes { raw in
            buds.rfcommChannelData(nil, data: raw.baseAddress, length: raw.count)
        }
    }

    /// The app's own dark surface, brought the way `Surface.window` brings it: every colour in
    /// `Theme` assumes a dark background, so a component drawn without it renders
    /// white-on-white and the golden would pin the wrong colours. The padding goes on the
    /// content rather than on the `ZStack`, so the background stays full-bleed and the
    /// component is inset symmetrically — exactly the relationship `MainColumn` has to its
    /// background.
    private func onDarkSurface<V: View>(_ content: V, padding: CGFloat = 16) -> AnyView {
        AnyView(
            ZStack {
                PremiumBackground()
                content.padding(padding)
            }
            .premiumSurface())
    }

    func testComponentSurfacesMatchTheirGoldenImages() throws {
        for component in componentGoldens {
            let rendered = try XCTUnwrap(
                Snapshots.png(component.view(), width: component.width),
                "\(component.name): ImageRenderer produced nothing")
            let goldenURL = componentGoldenDirectory.appendingPathComponent("\(component.name).png")

            if ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] != nil
                || !FileManager.default.fileExists(atPath: goldenURL.path) {
                try FileManager.default.createDirectory(at: componentGoldenDirectory,
                                                        withIntermediateDirectories: true)
                try rendered.write(to: goldenURL)
                continue
            }

            let golden = try Data(contentsOf: goldenURL)
            let difference = try compare(rendered, golden)
            XCTAssertLessThan(
                difference.ratio, 0.005,
                """
                \(component.name) no longer matches Tests/Goldens/\(component.name).png: \
                \(difference.pixels) of \(difference.total) pixels differ \
                (\(String(format: "%.2f", difference.ratio * 100))%). \
                It pins: \(component.state). If the change is intended, regenerate with \
                UPDATE_SNAPSHOTS=1 and read the diff.
                """)
        }
    }

    /// The component goldens are only meaningful if each seed actually reached the state the
    /// golden claims. A capture replayed under the wrong name, or a state that turned out not
    /// to be reachable, would otherwise pin the right pixels for the wrong reason — which is
    /// worse than no golden, because it reads as coverage.
    func testComponentSurfacesAreSeededFromTheRealCorpus() {
        let nc = seeded(.connected)
        ingest("anc-reply-nc-high", into: nc)
        XCTAssertEqual(nc.mode, .noiseCancellation, "the level row is pinned in the wrong mode")
        XCTAssertEqual(nc.ancLevel, .high)

        let flat = seeded(.connected)
        ingest("basswave-reply-0", into: flat)
        XCTAssertEqual(flat.bassWave, 0, "the flat golden is not flat")

        let warming = seeded(.warmingUp)
        XCTAssertTrue(warming.isConnected)
        XCTAssertFalse(warming.isControlChannelOpen)
        XCTAssertNil(warming.firmware, "the firmware-unknown golden has a firmware")

        let paired = seeded(.disconnected)
        XCTAssertTrue(paired.isPaired)
        XCTAssertFalse(paired.isConnected)
        let unpaired = Buds()
        XCTAssertFalse(unpaired.isPaired, "a fresh Buds is paired; the unpaired note is wrong")

        let withCase = seeded(.connected)
        XCTAssertTrue(withCase.isCaseReported, "the case goldens have no case to show")
        XCTAssertNil(withCase.battery.enclosure, "the case charge is known; it should be unread")

        let closed = seeded(.connected)
        closed.rfcommChannelClosed(nil)
        XCTAssertFalse(closed.isControlChannelOpen)
        XCTAssertNotNil(closed.battery.left, "no reading held, so the reconnect wording is wrong")
        XCTAssertNotNil(closed.mode)

        // The popup's two branches: readings in, and the instant before they arrive.
        let popup = seeded(.connected)
        XCTAssertNotNil(popup.battery.left, "the popup would draw a dash, not a reading")
        XCTAssertNotNil(popup.battery.right)
        XCTAssertNil(popup.battery.enclosure,
                     "the popup would draw a third cell; the capture carries no case charge")
        let popupWaiting = seeded(.warmingUp)
        XCTAssertNil(popupWaiting.battery.left)
        XCTAssertFalse(popupWaiting.isControlChannelOpen,
                       "the popup would show dashes where it should say it is reading")
    }

    private struct Difference {
        var pixels: Int
        var total: Int
        var ratio: Double { total == 0 ? 0 : Double(pixels) / Double(total) }
    }

    /// Counts pixels that differ by more than `tolerance` on any channel.
    private func compare(_ lhs: Data, _ rhs: Data, tolerance: Int = 2) throws -> Difference {
        let left = try XCTUnwrap(NSBitmapImageRep(data: lhs), "rendered PNG did not decode")
        let right = try XCTUnwrap(NSBitmapImageRep(data: rhs), "golden PNG did not decode")

        // Dimensions are not subject to tolerance: a surface that changed size is a different
        // layout, not a slightly different render.
        XCTAssertEqual(left.pixelsWide, right.pixelsWide, "rendered width changed")
        XCTAssertEqual(left.pixelsHigh, right.pixelsHigh, "rendered height changed")

        let width = min(left.pixelsWide, right.pixelsWide)
        let height = min(left.pixelsHigh, right.pixelsHigh)
        var differing = 0

        for y in 0..<height {
            for x in 0..<width {
                guard let a = left.colorAt(x: x, y: y), let b = right.colorAt(x: x, y: y) else {
                    continue
                }
                let dr = abs(a.redComponent - b.redComponent)
                let dg = abs(a.greenComponent - b.greenComponent)
                let db = abs(a.blueComponent - b.blueComponent)
                let da = abs(a.alphaComponent - b.alphaComponent)
                let allowed = Double(tolerance) / 255.0
                if dr > allowed || dg > allowed || db > allowed || da > allowed {
                    differing += 1
                }
            }
        }
        return Difference(pixels: differing, total: width * height)
    }
}
