import AppKit
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
/// The goldens live in `docs/assets`, which is also the website's asset directory, so the
/// screenshot a visitor sees is byte-for-byte the one this test verifies.
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
