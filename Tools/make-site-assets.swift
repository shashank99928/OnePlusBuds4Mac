#!/usr/bin/env swift
//
// Renders the website's marketing art from images the app itself produced.
//
// Two pieces, both derived from the golden screenshots in `docs/assets` rather than from
// hand-cut exports, so they cannot show a UI that no longer exists:
//
//   hero.jpg   the top of the window column, cropped to a shape that works above the fold
//   og.png     the 1200×630 social card, composed from the app icon and that crop
//
// It also writes a JPEG derivative of each golden, because PNG-encoding a screenshot of a flat
// dark interface costs about eight times what JPEG does for a difference a colour picker would
// have to find.
//
// The screenshots themselves come from `--render-snapshots`; run that first.
//
// Run:  swift Tools/make-site-assets.swift
//
import AppKit
import SwiftUI

// Adapted from Sources/BudsBarKit/Theme.swift, so the art and the app are the same blue.
private let accent = Color(red: 0.36, green: 0.60, blue: 1.00)
private let backgroundTop = Color(red: 0.055, green: 0.125, blue: 0.285)
private let backgroundBottom = Color(red: 0.027, green: 0.055, blue: 0.150)

private let heroCropHeight: CGFloat = 1180
private let cardSize = CGSize(width: 1200, height: 630)

private func load(_ path: String) -> NSImage? {
    guard let image = NSImage(contentsOfFile: path) else {
        FileHandle.standardError.write(Data("missing image: \(path)\n".utf8))
        return nil
    }
    return image
}

/// Crops from the top. `CGImage.cropping` measures from the top-left, which is what the hero
/// wants: the window's header, its battery reading and its noise-control pills.
private func cropTop(_ image: NSImage, height: CGFloat) -> NSImage? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let rect = CGRect(x: 0, y: 0,
                      width: CGFloat(cg.width),
                      height: min(height, CGFloat(cg.height)))
    guard let cropped = cg.cropping(to: rect) else { return nil }
    let rep = NSBitmapImageRep(cgImage: cropped)
    rep.size = NSSize(width: rect.width, height: rect.height)
    let out = NSImage(size: rep.size)
    out.addRepresentation(rep)
    return out
}

private func png(_ image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

/// JPEG at a quality that keeps the dark gradients clean. The screenshots are mostly flat
/// colour and text, and PNG-encoding them costs ~900 KB each where JPEG costs ~120 KB, for
/// differences that need a colour picker to find. `docs/assets` therefore holds both: the
/// goldens as PNG (lossless, because a pixel comparison needs them lossless) and the web
/// derivatives as JPEG, produced here in the same run so a derivative cannot show a UI the
/// goldens do not.
private func jpeg(_ image: NSImage, quality: CGFloat) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
}

@MainActor
private func render(_ view: some View, size: CGSize) -> NSImage? {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
    return renderer.nsImage
}

/// The screenshot, presented the way the site presents it: a rounded window with a shadow.
private struct FramedShot: View {
    let shot: NSImage
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = 20

    var body: some View {
        Image(nsImage: shot)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .clipped()
    }
}

private struct SocialCard: View {
    let icon: NSImage
    let shot: NSImage

    var body: some View {
        ZStack {
            LinearGradient(colors: [backgroundTop, backgroundBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // The same glow the app's own background uses.
            RadialGradient(colors: [accent.opacity(0.30), .clear],
                           center: UnitPoint(x: 0.12, y: 0.05),
                           startRadius: 0, endRadius: 760)

            HStack(spacing: 48) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                        Text("OnePlus Buds 4 for macOS")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                    }

                    Text("Your earbuds,\nfrom your Mac.")
                        .font(.system(size: 66, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(-2)

                    Text("Noise control, Sound Master EQ, BassWave, gestures and find-my-earbuds.")
                        .font(.system(size: 23))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("macOS 26  ·  Apple silicon  ·  MIT")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 4)
                }
                .frame(width: 600, alignment: .leading)

                FramedShot(shot: shot, width: 372, height: 486, radius: 24)
                    .shadow(color: .black.opacity(0.55), radius: 34, y: 18)
                    .overlay(
                        // Lifts the window off the gradient the way the app lifts a card.
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .padding(.horizontal, 68)
        }
    }
}

@MainActor
func main() {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: fm.currentDirectoryPath)
    let assets = root.appendingPathComponent("docs/assets")

    guard let window = load(assets.appendingPathComponent("window.png").path),
          let icon = load(assets.appendingPathComponent("icon.png").path) else {
        FileHandle.standardError.write(Data(
            "run `swift Tools/make-icon.swift` and `--render-snapshots` first\n".utf8))
        exit(1)
    }

    // Web derivatives of every golden, plus the hero, which is the window cropped to the part
    // that fits above the fold.
    //
    // The goldens are enumerated from the directory rather than listed here: a hand-maintained
    // list stops covering a surface the moment one is added, and the failure is silent on both
    // sides — no web image, and an `<img>` in the site pointing at a file that is not there.
    guard let hero = cropTop(window, height: heroCropHeight) else {
        FileHandle.standardError.write(Data("failed to crop the hero\n".utf8))
        exit(1)
    }

    // Not goldens: the icon, the favicon and the social card are written elsewhere, the
    // window's derivative is named explicitly because the hero is cropped from it, and the
    // sculpture is drawn by Tools/make-sculpture.swift and consumed by the WebGL hero as-is —
    // re-encoding it to JPEG would put a second, lossier copy of it on the site.
    let notGoldens: Set<String> = ["icon.png", "favicon.png", "og.png", "window.png", "sculpture.png"]
    let goldenNames = ((try? FileManager.default.contentsOfDirectory(atPath: assets.path)) ?? [])
        .filter { $0.hasSuffix(".png") && !notGoldens.contains($0) }
        .sorted()

    let derivatives: [(String, NSImage)] = [
        ("window.jpg", window),
        ("hero.jpg", hero),
    ] + goldenNames.compactMap { name in
        load(assets.appendingPathComponent(name).path)
            .map { (name.replacingOccurrences(of: ".png", with: ".jpg"), $0) }
    }

    for (name, image) in derivatives {
        guard let data = jpeg(image, quality: 0.86) else {
            FileHandle.standardError.write(Data("failed to encode \(name)\n".utf8))
            exit(1)
        }
        try! data.write(to: assets.appendingPathComponent(name))
        print("wrote docs/assets/\(name)")
    }

    guard let card = render(SocialCard(icon: icon, shot: hero), size: cardSize),
          let cardData = png(card) else {
        FileHandle.standardError.write(Data("failed to render the social card\n".utf8))
        exit(1)
    }
    try! cardData.write(to: assets.appendingPathComponent("og.png"))
    print("wrote docs/assets/og.png  (\(Int(cardSize.width))×\(Int(cardSize.height)))")
}

await MainActor.run { main() }
