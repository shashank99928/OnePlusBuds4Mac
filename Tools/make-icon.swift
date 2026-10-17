#!/usr/bin/env swift
//
// Renders the app icon and packs it into Resources/AppIcon.icns.
//
// The artwork is expressed in SwiftUI and rasterised with ImageRenderer, since that
// gives the continuous-corner "squircle" macOS expects — a plain rounded rect from
// CoreGraphics is visibly wrong next to native icons.
//
// Run:  swift Tools/make-icon.swift
//
import AppKit
import SwiftUI

// Adapted from Sources/BudsBarKit/Theme.swift — the icon is the app's look in miniature, so
// the accent and the gradient are the same values, with the top of the gradient lifted a
// little because at icon size the app's darker top reads as flat black.
private let accent = Color(red: 0.36, green: 0.60, blue: 1.00)
private let backgroundTop = Color(red: 0.10, green: 0.21, blue: 0.46)
private let backgroundBottom = Color(red: 0.027, green: 0.055, blue: 0.150)

/// Apple's macOS app-icon grid: the squircle occupies 824 of 1024 points, radius 186.
private func iconMetrics(_ size: CGFloat) -> (inset: CGFloat, body: CGFloat, radius: CGFloat) {
    let inset = size * (100.0 / 1024.0)
    return (inset, size - inset * 2, size * (186.0 / 1024.0))
}

private struct IconArt: View {
    let size: CGFloat

    var body: some View {
        let m = iconMetrics(size)
        let shape = RoundedRectangle(cornerRadius: m.radius, style: .continuous)

        shape
            .fill(LinearGradient(colors: [backgroundTop, backgroundBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.fill(RadialGradient(
                    colors: [accent.opacity(0.55), .clear],
                    center: UnitPoint(x: 0.5, y: 0.16),
                    startRadius: 0, endRadius: m.body * 0.72)))
            .overlay(
                Image(systemName: "earbuds")
                    .font(.system(size: size * 0.40, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: accent.opacity(0.9), radius: size * 0.05))
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.16), lineWidth: max(1, size * 0.004)))
            .frame(width: m.body, height: m.body)
            .frame(width: size, height: size)
    }
}

@MainActor
private func png(_ size: Int) -> Data? {
    let renderer = ImageRenderer(content: IconArt(size: CGFloat(size)))
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

/// (filename, pixel size) — the ten entries `iconutil` wants.
private let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

/// The same art, for the website and the social card. Written from the same renderer as the
/// `.icns` so the icon in the README, the icon on the site and the icon in the Dock cannot
/// become three different squircle gradients.
private let siteVariants: [(String, Int)] = [
    ("icon.png", 512),
    ("favicon.png", 128),
]

await MainActor.run {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: fm.currentDirectoryPath)
    let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
    let icns = root.appendingPathComponent("Resources/AppIcon.icns")
    let siteAssets = root.appendingPathComponent("docs/assets")

    try? fm.removeItem(at: iconset)
    try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    try? fm.createDirectory(at: siteAssets, withIntermediateDirectories: true)

    for (name, size) in variants {
        guard let data = png(size) else {
            FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
            exit(1)
        }
        try! data.write(to: iconset.appendingPathComponent(name))
    }

    for (name, size) in siteVariants {
        guard let data = png(size) else {
            FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
            exit(1)
        }
        try! data.write(to: siteAssets.appendingPathComponent(name))
        print("wrote docs/assets/\(name)")
    }
}

// iconutil has to run after the generator's own main-actor block, on the normal path.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    root.appendingPathComponent("Resources/AppIcon.iconset").path,
    "-o", root.appendingPathComponent("Resources/AppIcon.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("wrote Resources/AppIcon.icns")
