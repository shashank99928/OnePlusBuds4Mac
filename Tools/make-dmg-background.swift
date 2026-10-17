#!/usr/bin/env swift
//
// Renders the disk-image background used by make-dmg.sh.
//
// Two files are produced — `dmg-background.png` at 1x and `dmg-background@2x.png` at 2x.
// Finder picks the @2x on a Retina display automatically, the same way it does for
// regular app artwork, so the image stays sharp without the toolkit guessing at DPI.
//
// The window it is drawn for is 660x420; the app icon lands near x=165 and the
// Applications shortcut near x=495, both at y=205 (Finder counts y from the top).
//
// Run:  swift Tools/make-dmg-background.swift
//
import AppKit
import SwiftUI

private let accent = Color(red: 0.36, green: 0.60, blue: 1.00)

struct DmgBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.125, blue: 0.285),
                         Color(red: 0.027, green: 0.055, blue: 0.150)],
                startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [accent.opacity(0.30), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0, endRadius: 420)

            VStack(spacing: 6) {
                Text("OnePlus Buds 4")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Drag the app into Applications to install")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .position(x: 330, y: 74)

            Image(systemName: "arrow.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent.opacity(0.9))
                .shadow(color: accent.opacity(0.6), radius: 10)
                .position(x: 330, y: 205)

            Text("Requires macOS 26 or later  ·  Open source, MIT licensed")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.38))
                .position(x: 330, y: 386)
        }
        .frame(width: 660, height: 420)
    }
}

@MainActor
private func write(scale: CGFloat, to url: URL) {
    let renderer = ImageRenderer(content: DmgBackground())
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: 660 * scale, height: 420 * scale)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

await MainActor.run {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    write(scale: 1, to: root.appendingPathComponent("Resources/dmg-background.png"))
    write(scale: 2, to: root.appendingPathComponent("Resources/dmg-background@2x.png"))
}

print("wrote Resources/dmg-background.png and dmg-background@2x.png")
