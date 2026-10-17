#!/usr/bin/env swift
//
// Renders the hero's sculpture: a bundle of interwoven filaments, drawn procedurally and
// left on transparency.
//
// It is generated rather than borrowed, for the same reason the icon is: the site ships no
// third-party artwork. It is also transparency, not a flat background, because the particle
// engine on the page keys material by alpha — which is what lets the strands dissolve into
// particles over the page's own gradient with no colour matching between the two.
//
// The shape is a single braid: every strand converges on the same axis at both ends and
// swells apart in the middle, so the bundle reads as one woven object rather than as
// scattered lines.
//
// Run:  swift Tools/make-sculpture.swift     ->  docs/assets/sculpture.png
//
import AppKit
import SwiftUI

// The app's blue, plus the deep end and the highlight it ranges between, so the strands and
// the interface share a palette.
private let deep = (0.13, 0.30, 0.92)
private let accent = (0.36, 0.60, 1.00)
private let hot = (0.88, 0.94, 1.00)

private let artSize = CGSize(width: 1080, height: 640)
private let strandCount = 30
private let steps = 280

/// A reproducible generator: the file is byte-identical on every machine, which matters for
/// an asset that lives in the repository.
private struct Rng {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func unit() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_003) / 1_000_003
    }
    mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

private struct Strand {
    var band: Double        // where it sits across the bundle, -1...1
    var amplitude: Double   // its own wave, as a fraction of the height
    var cycles: Double
    var phase: Double
    var lineWidth: Double   // px, at its widest
    var shade: Double       // 0 = deep, 1 = highlight
    var beadRate: Double
    var beadPhase: Double
    var opacity: Double
}

private func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double)
    -> Color {
    let k = min(1, max(0, t))
    return Color(red: a.0 + (b.0 - a.0) * k,
                 green: a.1 + (b.1 - a.1) * k,
                 blue: a.2 + (b.2 - a.2) * k)
}

/// Deep -> accent -> highlight, so the bundle carries a light through it.
private func ramp(_ k: Double) -> Color {
    let t = min(1, max(0, k))
    return t < 0.5 ? mix(deep, accent, t * 2) : mix(accent, hot, (t - 0.5) * 2)
}

/// The axis the whole braid is tied to: nearly straight, with one slow sweep.
private func axis(_ t: Double, _ h: Double) -> Double {
    (0.5 + 0.055 * sin(2 * .pi * 0.62 * t + 0.35)) * h
}

/// The bundle pinches to nothing at both ends, which is what makes it a braid.
private func taper(_ t: Double) -> Double {
    pow(sin(.pi * min(1, max(0, t))), 0.72)
}

private func point(_ s: Strand, _ t: Double, _ w: Double, _ h: Double) -> CGPoint {
    let pinch = taper(t)
    let wave = s.amplitude * h * sin(2 * .pi * s.cycles * t + s.phase) * pinch
    let y = axis(t, h) + s.band * 0.38 * h * pinch + wave
    return CGPoint(x: t * w, y: y)
}

private func lineWidth(_ s: Strand, _ t: Double) -> Double {
    let ripple = 0.55 + 0.75 * abs(sin(2 * .pi * s.beadRate * t + s.beadPhase))
    return s.lineWidth * (0.35 + 0.65 * taper(t)) * ripple
}

/// Fades at both ends, so the material thins out where the braid pinches.
private func fade(_ t: Double) -> Double {
    0.14 + 0.86 * pow(sin(.pi * min(1, max(0, t))), 0.42)
}

/// A strand rising to the left catches the light; one falling away goes deep.
private func colour(_ s: Strand, _ t: Double, _ w: Double, _ h: Double) -> Color {
    let d = 0.004
    let a = point(s, t - d, w, h)
    let b = point(s, t + d, w, h)
    let slope = (b.y - a.y) / max(b.x - a.x, 0.001)
    let lift = min(1, max(-1, -slope * 26))
    return ramp(s.shade + 0.38 * lift)
}

private func makeStrands() -> [Strand] {
    var rng = Rng(seed: 0x0B4D5)
    return (0..<strandCount).map { i in
        let n = Double(i) / Double(strandCount - 1)          // 0...1 across the bundle
        return Strand(
            band: rng.between(-1, 1),
            amplitude: rng.between(0.02, 0.10),
            cycles: rng.between(0.7, 2.6),
            phase: rng.between(0, 2 * .pi),
            lineWidth: rng.between(1.6, 5.4),
            // Strands are brighter towards the top of the bundle, as if lit from above.
            shade: min(1, max(0, 0.42 * (1 - n) + rng.between(-0.16, 0.30))),
            beadRate: rng.between(3, 11),
            beadPhase: rng.between(0, 2 * .pi),
            opacity: rng.between(0.55, 1.0))
    }
}

private struct Sculpture: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let strands = makeStrands()

            // No bloom pass here on purpose: a blurred duplicate of the braid is most of the
            // file size (about 2.5x, for a glow the particle engine reproduces the moment the
            // material is disturbed). The strands carry their own light instead.

            // The strands, in segments, because the width and the light both vary along the
            // length.
            let seg = 150
            for s in strands {
                for i in 0..<seg {
                    let t0 = Double(i) / Double(seg)
                    let t1 = Double(i + 1) / Double(seg)
                    var path = Path()
                    path.move(to: point(s, t0, w, h))
                    path.addLine(to: point(s, t1, w, h))
                    let lw = (lineWidth(s, t0) + lineWidth(s, t1)) / 2
                    let a = (fade(t0) + fade(t1)) / 2 * s.opacity
                    ctx.stroke(path, with: .color(colour(s, (t0 + t1) / 2, w, h).opacity(a)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
            }

            // Beads of the same material, scattered along the strands.
            var beadRng = Rng(seed: 0x5EED)
            for s in strands {
                var t = 0.02
                while t < 0.98 {
                    let p = point(s, t, w, h)
                    let r = beadRng.between(0.7, 2.5)
                    let a = beadRng.between(0.35, 1.0) * fade(t)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                        with: .color(colour(s, t, w, h).opacity(a)))
                    t += beadRng.between(0.014, 0.05)
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height)
    }
}

@MainActor
func main() {
    let renderer = ImageRenderer(content: Sculpture())
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else {
        FileHandle.standardError.write(Data("failed to render the sculpture\n".utf8))
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: artSize.width, height: artSize.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode the sculpture\n".utf8))
        exit(1)
    }
    let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/assets/sculpture.png")
    try! data.write(to: out)
    print("wrote docs/assets/sculpture.png  (\(Int(artSize.width))×\(Int(artSize.height)))")
}

await MainActor.run { main() }
