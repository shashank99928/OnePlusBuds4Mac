import AppKit
import SwiftUI

/// Identity constants, so the name and the version live in exactly one place.
enum AppInfo {
    static let name = "OnePlus Buds 4"
    /// Scene id for the main window; used to re-open it.
    static let mainWindowID = "main"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

/// Entry point.
///
/// The app lives in a library target so the protocol — and the views — can be exercised by
/// `swift test`; the executable target is four lines because of it (see
/// `Sources/OnePlusBuds4/main.swift`). That costs one `public` symbol and buys the checks a
/// place to run that is not "at launch, in the app the user is trying to use".
public enum BudsBar {
    @MainActor
    public static func launch() {
        // Handled here rather than in `applicationDidFinishLaunching` so a check run never
        // constructs NSApplication, a status item, a popover, or a Bluetooth session. The
        // previous version checked after the app had already started — which is why a broken
        // fixture took the running app down with it instead of printing a failure.
        if BudsProtocol.isSelfCheckRun { BudsProtocol.runSelfCheckAndExit() }
        // Same idea: draw the surfaces and exit, with no app behind it.
        if Buds.isRenderingSnapshots { Snapshots.renderAndExit() }
        BudsBarApp.main()
    }
}

struct BudsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The app now ships two surfaces. This is the window: a real, resizable window
        // with a Dock presence, so the app is usable like any other Mac app. The
        // menu-bar item is still owned by the delegate (see `AppDelegate`), which keeps
        // its ability to disappear along with the buds.
        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            MainWindowContent(buds: delegate.buds)
        }
        .defaultSize(width: 470, height: 740)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }
    }
}

/// Hosts the window content and hands its `openWindow` action to the bridge, so AppKit
/// code (the status item, Dock re-open) can summon the window too.
private struct MainWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    let buds: Buds

    var body: some View {
        MainWindowView(buds: buds)
            .onAppear {
                MainWindowBridge.shared.register { openWindow(id: AppInfo.mainWindowID) }
            }
    }
}

/// Re-opens the main window from outside SwiftUI.
///
/// SwiftUI owns the window, so the only supported way to show it again is its
/// `openWindow` action. That action is captured once the window first appears and stays
/// valid for the life of the app — including after the window has been closed — so
/// storing it is enough. The fallback covers the window never having appeared at all.
@MainActor
final class MainWindowBridge {
    static let shared = MainWindowBridge()

    private var open: (() -> Void)?

    func register(_ action: @escaping () -> Void) { open = action }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let open {
            open()
        } else {
            NSApp.windows
                .first { $0.canBecomeMain && !($0 is NSPanel) }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

/// The File menu. `newItem` is repurposed because "New" means nothing here — the app has
/// one window — but a way to bring it up is exactly what belongs there.
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open \(AppInfo.name)") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppInfo.mainWindowID)
            }
            .keyboardShortcut("o")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    /// Shared by the window scene and the status item — one connection, two surfaces.
    let buds = Buds()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let floating = FloatingPanelController()
    /// nil until the first sync, so the icon is always drawn once at launch.
    private var lastIconConnected: Bool?
    private var outsideClickMonitor: Any?
    /// Tracks connection transitions so the AirPods-style popup only appears on a new connect.
    private var wasConnected = false
    /// Pending hide, so removal can be debounced. See `syncStatusItem`.
    private var hideWorkItem: DispatchWorkItem?

    /// How long unavailability must persist before the item is removed. The link genuinely
    /// bounces during a quick off→on — the old session's teardown notifications land after
    /// the new link is up and knock it down for a second or two before it recovers — and the
    /// item must ride that out rather than flicker away. A case being shut does not recover,
    /// so the item still disappears, just this much later.
    private static let hideDelay: TimeInterval = 6

    func applicationWillTerminate(_ notification: Notification) {
        buds.shutdown()
    }

    /// Debug-build reporting of the protocol checks. Loud on failure, but not fatal: a broken
    /// check in a running build is easier to diagnose than an app that refuses to start.
    private func report(_ result: BudsProtocol.SelfCheckResult) {
        for failure in result.failures {
            FileHandle.standardError.write(Data("selfCheck FAILED: \(failure)\n".utf8))
        }
        if result.passed {
            FileHandle.standardError.write(
                Data("selfCheck passed: \(result.checks) checks\n".utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--selfcheck` never gets this far: `BudsBar.launch()` intercepts it before
        // NSApplication exists. What is left is the debug-only report, so a broken check is
        // visible while developing without an app that refuses to start.
        #if DEBUG
        report(BudsProtocol.selfCheck())
        #endif

        // The design is a dark "night" surface, so pin the app to dark rather than let a
        // light system appearance wash it out. This also darkens the window chrome and the
        // popover so the whole app reads as one piece.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Not `.transient`: that closes the popover whenever the app resigns active, and
        // connecting or disconnecting the buds shuffles activation enough to trip it — the
        // panel vanished the instant the power toggle was used. Dismissal is handled here
        // instead, by watching for a click outside.
        popover.behavior = .applicationDefined
        popover.delegate = self
        // `.applicationDefined` also switches off the framework's own key handling, so Escape
        // no longer closed the panel — a popover that traps the pointer has to be dismissable
        // from the keyboard. `onExitCommand` is SwiftUI's Escape; the click-outside monitor
        // below still handles the mouse.
        popover.contentViewController = NSHostingController(
            rootView: PanelView(buds: buds).onExitCommand { [weak self] in
                self?.popover.performClose(nil)
            })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        buds.onStateChange = { [weak self] in
            self?.syncStatusItem()
            guard let self else { return }
            let now = self.buds.isConnected
            if now && !self.wasConnected { self.floating.show(buds: self.buds) }
            self.wasConnected = now
        }
        self.wasConnected = buds.isConnected
        syncStatusItem()
    }

    /// The window is a first-class surface now, so the app must not quit when it is
    /// closed — the status item stays, and the window can be re-opened from it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon should bring the window back rather than do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowBridge.shared.show() }
        return true
    }

    /// Adds or removes the item, and keeps its glyph in step. Driven by `Buds`' own poll, so
    /// it runs every couple of seconds — hence the early-outs when nothing actually moved.
    ///
    /// The two checks are deliberately separate. Assigning `isVisible` rebuilds the status
    /// item's window, which dismisses a popover anchored to its button — so switching the
    /// buds off, which changes the icon but not whether the item belongs on screen, must not
    /// go anywhere near it. Writing the same value counts: the setter does the work anyway.
    private func syncStatusItem() {
        // `onStateChange` can in principle fire from Buds' own init work before
        // `applicationDidFinishLaunching` has created the item.
        guard let statusItem else { return }

        if buds.isAvailable {
            // Showing is immediate; any pending hide was a bounce and is void.
            hideWorkItem?.cancel()
            hideWorkItem = nil
            if !statusItem.isVisible {
                statusItem.isVisible = true
                // Re-insertion can rebuild the item's window, so the glyph cannot be
                // trusted to have survived — forget it and let the check below redraw.
                lastIconConnected = nil
            }
        } else if statusItem.isVisible, hideWorkItem == nil {
            // Hiding is debounced: only an outage that outlives the delay is real.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hideWorkItem != nil else { return }
                self.hideWorkItem = nil
                guard !self.buds.isAvailable else { return }
                self.statusItem.isVisible = false
                if self.popover.isShown { self.popover.performClose(nil) }
                self.lastIconConnected = nil
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
        }

        if statusItem.isVisible, lastIconConnected != buds.isConnected {
            lastIconConnected = buds.isConnected
            statusItem.button?.image = menuBarIcon
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // The panel is rebuilt from live state each time it opens rather than showing
        // whatever it last rendered.
        buds.refreshConnectionState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Stands in for `.transient`'s click-away dismissal. A global monitor sees only
        // events destined for other apps, so clicks inside the panel — the toggle, the mode
        // buttons — never reach it. Mouse events need no Accessibility grant; key events do.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// The menu bar glyph.
    ///
    /// Disconnected is drawn in red, which means giving up template rendering for that
    /// state: the menu bar recolours a template image to match itself, so a red one would
    /// come out plain monochrome. Connected stays a template so it still follows the menu
    /// bar's own light/dark appearance.
    ///
    /// `airpods.pro.chargingcase.fill` — the name used here before — is not a real symbol,
    /// which is why the disconnected icon was blank. The `.wireless` variant is the one
    /// that exists.
    ///
    /// Both states come from the `earbud.*` family the rest of the app uses: `earbuds.case.fill`
    /// when connected, `earbuds.case` when not. The pair is deliberate — filled against outline is
    /// the state, and it survives a monochrome menu bar, a screenshot and a colour-blind reader.
    /// Colour alone would not: the red tint is emphasis on top, not the signal. (`earbuds.fill` for
    /// the bare pair does not exist, which is why the case is the glyph for both.)
    private var menuBarIcon: NSImage {
        let name = buds.isConnected ? "earbuds.case.fill" : "earbuds.case"
        // The description is what VoiceOver reads; using the symbol name made it say
        // "earbuds.case.fill" rather than anything about the buds.
        let description = buds.isConnected ? "Earbuds connected" : "Earbuds disconnected"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()

        guard !buds.isConnected else {
            image.isTemplate = true
            return image
        }
        let red = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemRed])) ?? image
        red.isTemplate = false
        return red
    }
}
