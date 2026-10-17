import AppKit
import SwiftUI

/// Borderless floating panel used for the AirPods-style "just connected" battery popup.
final class FloatingPanelController {
    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    /// A fade is motion, and this one is decoration. AppKit exposes the system setting
    /// directly rather than through the SwiftUI environment, since this controller is not
    /// inside a view hierarchy.
    private var fadeDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
    }

    func show(buds: Buds) {
        if window == nil {
            let hosting = NSHostingController(rootView: FloatingBatteryView(buds: buds))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.contentViewController = hosting
            panel.isMovableByWindowBackground = true
            window = panel
        }
        guard let window else { return }

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24,
                                          y: visible.maxY - size.height - 24))
        }

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            window.animator().alphaValue = 0
        }, completionHandler: { window.orderOut(nil) })
    }
}
