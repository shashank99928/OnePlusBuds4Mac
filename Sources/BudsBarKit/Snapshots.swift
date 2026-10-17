import AppKit
import SwiftUI

/// True only while `ImageRenderer` is drawing the surfaces for a snapshot.
///
/// `ImageRenderer` draws SwiftUI's own primitives; an AppKit-backed control comes out as a
/// coloured placeholder bar. The three that appear in these views — `Menu` in the gesture rows
/// and the "…" button, and the `Toggle` in the settings row — read this and draw a static
/// label instead, so the image and the golden show the layout that actually ships.
///
/// Nothing in a running app ever sees this set.
private struct RenderingSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isRenderingSnapshot: Bool {
        get { self[RenderingSnapshotKey.self] }
        set { self[RenderingSnapshotKey.self] = newValue }
    }
}

/// Renders the app's surfaces to PNG at the widths they are actually used at.
///
/// Two jobs, one implementation. `--render-snapshots` writes the images the README and the
/// website show, and `SnapshotTests` compares those same files as golden images — so a padding
/// change that makes the 340pt panel clip fails a test instead of being noticed by eye three
/// commits later. Exact widths because that is the whole point: the panel is a fixed 340pt
/// column and the window has a minimum, and both are where a layout breaks.
///
/// The images live in `docs/assets`, which is the site's asset directory, rather than in
/// `Tests/`: the picture a visitor sees and the picture the test verifies are then the same
/// file, so there is no second copy to drift. The test fails if one no longer matches what the
/// app draws.
///
/// The views are drawn from a `Buds` seeded with the decoded fixture corpus (see
/// `seedForSnapshot`), so the images show real readings from this hardware rather than
/// plausible-looking invented ones.
///
/// Known limitation: `ImageRenderer` draws SwiftUI's own primitives, not AppKit-backed
/// controls. A `Menu` or a `Toggle` inside a rendered view comes out blank, which is why those
/// controls draw a static label while `isRenderingSnapshot` is set. The golden images therefore
/// cover layout, typography and colour — which is what silently breaks — and not the contents
/// of a menu.
enum Snapshots {
    enum Surface: String, CaseIterable {
        /// The main window's scrolling column at the width the README shows it.
        case window
        /// The menu-bar popover, exactly as wide as it is on screen.
        case panel
        /// The same popover in the first second after connecting, before anything has been
        /// read off the buds. Rendered because it is the state most likely to be left as a
        /// grid of dashes that read as faults, and the least likely to be looked at by hand.
        case panelWarming = "panel-warming"
        /// The same popover with the buds off: paired, link down, nothing read. It is the state a
        /// person looks at most of the time, so it is the one that most needs its empty state to
        /// say something rather than show dashes.
        case panelDisconnected = "panel-disconnected"

        var state: Buds.SnapshotState {
            switch self {
            case .window, .panel: return .connected
            case .panelWarming: return .warmingUp
            case .panelDisconnected: return .disconnected
            }
        }

        var width: CGFloat {
            switch self {
            case .panel, .panelWarming, .panelDisconnected: return 340
            case .window: return 470
            }
        }

        @MainActor func content(_ buds: Buds) -> AnyView {
            switch self {
            case .panel, .panelWarming, .panelDisconnected:
                // `PanelView` brings its own background and surface.
                return AnyView(PanelView(buds: buds))
            case .window:
                // The window's `ScrollView` cannot be rasterised, so the README shows the
                // column instead — which means bringing the background the frame would have
                // supplied. Without it the palette renders white-on-white: every colour in
                // `Theme` assumes a dark surface.
                return AnyView(
                    ZStack {
                        PremiumBackground()
                        MainColumn(buds: buds)
                    }
                    .premiumSurface())
            }
        }
    }

    @MainActor
    static func image(_ surface: Surface) -> NSImage? {
        let buds = Buds()
        buds.seedForSnapshot(surface.state)
        let renderer = ImageRenderer(
            content: surface.content(buds)
                .frame(width: surface.width)
                // `ImageRenderer` cannot rasterise AppKit-backed controls — a `Menu` or a
                // `Toggle` comes out as a coloured placeholder bar, which would make the
                // README image and the golden both look broken. The affected controls
                // substitute a static label while this is set; see `isRenderingSnapshot`.
                .environment(\.isRenderingSnapshot, true))
        renderer.scale = 2
        return renderer.nsImage
    }

    /// PNG bytes — what the golden test compares.
    @MainActor
    static func png(_ surface: Surface) -> Data? {
        guard let image = image(surface),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for surface in Surface.allCases {
            guard let data = png(surface) else {
                throw SnapshotError.nothingRendered(surface.rawValue)
            }
            try data.write(to: directory.appendingPathComponent("\(surface.rawValue).png"))
        }
    }

    enum SnapshotError: Error, CustomStringConvertible {
        case nothingRendered(String)

        var description: String {
            switch self {
            case .nothingRendered(let name): return "\(name): ImageRenderer produced nothing"
            }
        }
    }

    /// `--render-snapshots [directory]` — draws every surface and exits.
    ///
    /// Handled from `BudsBar.launch()` before anything else, so no window, no status item and
    /// no radio session is ever created for it.
    ///
    /// The default directory is the golden directory on purpose: the images the README shows
    /// and the images the test compares are then the same files, so there is no second copy to
    /// go stale, and `swift test` fails if one of them no longer matches what the app draws.
    @MainActor
    static func renderAndExit() -> Never {
        let arguments = CommandLine.arguments
        let path = arguments.firstIndex(of: "--render-snapshots").flatMap { index in
            let next = index + 1
            guard arguments.indices.contains(next), !arguments[next].hasPrefix("-") else {
                return nil
            }
            return arguments[next]
        } ?? "docs/assets"

        do {
            try write(to: URL(fileURLWithPath: path))
            print("wrote \(Surface.allCases.count) snapshots to \(path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot render failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
