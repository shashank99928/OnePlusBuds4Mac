import Foundation
import IOBluetooth
import Observation

/// Live state of the earbuds plus the Bluetooth plumbing that produces it.
///
/// Two independent links are involved:
///   - the baseband connection (`openConnection`/`closeConnection`), which is what the
///     power toggle in the UI drives, and
///   - the vendor RFCOMM control channel (`oppointeraction`), which carries noise-control
///     and per-bud battery. The latter only exists while the former is up.
@Observable
final class Buds: NSObject, IOBluetoothRFCOMMChannelDelegate {

    /// Raw protocol logging, off unless asked for — the buds push status every few seconds.
    static let isTracing = ProcessInfo.processInfo.environment["BUDSBAR_TRACE"] != nil

    /// True for a `--selfcheck` run: the binary is the app, but the job is a protocol test, so
    /// it must not page the buds or open a control channel.
    static let isSelfChecking = CommandLine.arguments.contains("--selfcheck")

    /// True for `--render-snapshots`: the binary draws the two surfaces to PNG and exits, so
    /// there is nothing to connect to and a radio session would only make it slow.
    static let isRenderingSnapshots = CommandLine.arguments.contains("--render-snapshots")

    /// True inside a test process.
    ///
    /// A test run must not open a control channel. The channel is exclusive, so `swift test`
    /// on a machine with the buds connected would take it away from the app that is using it
    /// (or from the phone app), and any pixel comparison would then depend on whatever the
    /// hardware happened to answer. The test process carries no command-line flags of its own,
    /// which is why this cannot be folded into the checks above.
    static let isTesting = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// True when the process is doing something other than being the app. A protocol check, a
    /// snapshot render and a test run all construct `Buds`, and none of them wants a paging
    /// attempt, a poll timer and an RFCOMM session behind it.
    ///
    /// `isHarvesting` is deliberately not included: capturing fixtures is the one thing that
    /// genuinely needs the radio.
    static let isDetached = isSelfChecking || isRenderingSnapshots || isTesting

    /// Drives a fixed sequence so a raw-frame capture contains one clean example of every
    /// frame type. Fixtures are captured, never typed: every hand-written one so far has had
    /// length fields that disagree with its own bytes.
    static let isHarvesting = ProcessInfo.processInfo.environment["BUDSBAR_HARVEST"] != nil

    /// SDP service UUID for OPPO/realme's `oppointeraction` control service.
    /// realme is an OPPO sub-brand and shares the protocol.
    private static let controlServiceUUID: [UInt8] = [
        0x00, 0x00, 0x07, 0x9a, 0xd1, 0x02, 0x11, 0xe1,
        0x9b, 0x23, 0x00, 0x02, 0x5b, 0x00, 0xa5, 0xa5,
    ]

    // MARK: - Published state

    static let fallbackName = "OnePlus Buds 4"

    var name: String = Buds.fallbackName
    /// Guards the one-shot background lookup in `syncName`; cleared on a new link.
    private var hasReadDisplayName = false
    var isConnected = false
    /// True once the vendor control channel is open — noise control needs it.
    var isControlChannelOpen = false
    var battery = Battery()
    var placement = Placement()
    var mode: NoiseMode?
    /// How hard cancellation is working. Carried in the same mask as the mode, so it is
    /// always known while Noise cancellation is on.
    var ancLevel: ANCLevel?
    /// Sound Master EQ preset, as last read back.
    var eqPreset: EQPreset?
    /// The EQ preset is the custom profile, when one exists. Read-only: the upload format is
    /// decoded but has never been transmitted by anyone, and there is no documented way to
    /// delete a profile, so the app does not write one into the buds' flash.
    ///
    /// Tri-state, like every other reading: nil means the buds have not been asked, or the one
    /// `0x22` request went unanswered, and the About row must say "—" rather than "None". A
    /// definite `false` is a reply that said no profile is stored.
    var hasCustomEQProfile: Bool?
    /// BassWave level, −5…+5.
    var bassWave: Int?
    /// Firmware string, e.g. `1,2,138,2,2,138,3,1,01,3,2,105`.
    var firmware: String?
    /// The touch-gesture table, as read back. Written one record at a time.
    var touchRules: [BudsProtocol.TouchRule] = []
    /// Set while a connect/disconnect is in flight so the toggle can't be double-fired.
    var isBusy = false
    var lastError: String?

    /// Set when the power toggle was used to switch the buds off.
    ///
    /// Sticky, and it outranks every other signal — including frames still arriving on the
    /// control channel. A worn earbud re-pages the Mac within a second of `closeConnection`
    /// and macOS brings the audio link straight back up, so anything that reads the link as
    /// evidence of intent ends up undoing the switch-off the user just asked for. Off means
    /// off until the toggle is used again; only `connect()` clears this.
    private(set) var isSwitchedOff = false

    /// Set when a connect the *user* asked for failed, so the item stays on screen with the
    /// error on it. Deliberately not `isSwitchedOff`: that flag also stops the auto-connect
    /// poll, and the user asked for on — the buds are routinely slow to accept the first page
    /// after being dropped, so the retry is exactly what recovers it.
    private var didFailUserConnect = false

    /// Whether the menu bar item should exist at all.
    ///
    /// Classic Bluetooth has no way to ask whether a device is nearby short of paging it,
    /// and paging *is* connecting — `remoteNameRequest` answers from cache, so it cannot
    /// tell a closed case from an open one. So availability is inferred rather than probed:
    /// either the buds are connected, or they were switched off deliberately and the user
    /// needs the toggle to switch them back on. Buds sitting in a shut case are neither, and
    /// the item disappears.
    ///
    /// Busy counts too — but only when the attempt is the user's. Flipping the toggle back
    /// on clears `isSwitchedOff` before the link exists, and without the busy term the item
    /// would vanish the moment it was flipped. The background retry must NOT get the same
    /// courtesy: against a shut case openConnection() blocks for the full page timeout, so
    /// counting auto attempts kept resurfacing the red icon for ~10s of every 20.
    /// With nothing paired the item stays put regardless, so the panel can say why instead
    /// of the app being invisible and looking broken.
    var isAvailable: Bool {
        !isPaired || isConnected || isSwitchedOff || didFailUserConnect
            || (isBusy && !isAutoConnecting)
    }

    /// True while the in-flight connect attempt came from the poll rather than the user.
    private var isAutoConnecting = false

    /// False when no paired device speaks the control protocol — nothing to drive.
    var isPaired: Bool { isPairedOverride ?? (device != nil) }

    /// Snapshot-only: `seedForSnapshot` has no real `device`, so it forces pairing rather than
    /// rendering a state — connected but unpaired — that a live session cannot be in. nil in
    /// every live session, where pairing is whether a device was discovered.
    var isPairedOverride: Bool?

    /// Called whenever `isAvailable` or `isConnected` may have moved, so the status item can
    /// insert, remove, or recolour itself. A plain callback rather than observation: the
    /// owner is AppKit, not a SwiftUI view.
    var onStateChange: (() -> Void)?

    struct Battery {
        var left: Int?
        var right: Int?
        var enclosure: Int?
    }

    /// Where each bud is, as the buds report it. nil until they have said.
    ///
    /// This is what stops a bud charging in the case from being drawn as one in use. It also
    /// covers a gap in the battery report: a bud in the case drops out of it entirely rather
    /// than reporting as unknown, and an absent slot deliberately keeps its last value — so
    /// without placement the panel showed a frozen percentage for a bud that was put away.
    struct Placement {
        var left: BudsProtocol.BudPlacement?
        var right: BudsProtocol.BudPlacement?
        /// Where the case reported itself. Not a bud, but the wear report names the slot, and
        /// it is the only evidence the app has that a case exists at all — the battery report
        /// drops the case out entirely while it is asleep, which is most of the time.
        var enclosure: BudsProtocol.BudPlacement?

        subscript(slot: BudsProtocol.BatterySlot) -> BudsProtocol.BudPlacement? {
            get {
                switch slot {
                case .left: return left
                case .right: return right
                case .enclosure: return enclosure
                }
            }
            set {
                switch slot {
                case .left: left = newValue
                case .right: right = newValue
                case .enclosure: enclosure = newValue
                }
            }
        }
    }

    /// Whether a case is actually there.
    ///
    /// The wear report is the only evidence while the case is asleep — a sleeping case drops
    /// out of the battery report entirely, which is its usual state — but a slot reported as
    /// `.notPresent` means there is no case, not an unknown one, so it does not count. The two
    /// surfaces share this so neither invents a case the other has decided is absent.
    var isCaseReported: Bool {
        (placement.enclosure.map { $0 != .notPresent } ?? false) || battery.enclosure != nil
    }

    // MARK: - Private

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var rxBuffer: [UInt8] = []
    private var disconnectObserver: IOBluetoothUserNotification?
    /// True while `openControlChannel` has work in flight. See the note there.
    private var isOpening = false

    /// State for the `BUDSBAR_HARVEST=1` recon sweep.
    ///
    /// The sweep writes to real hardware, so it is guarded rather than assumed: `harvestHasRun`
    /// stops a reconnect mid-sweep from starting a second, overlapping one (it is scheduled per
    /// channel open), and `harvestWriteFailures` is why the sweep does not simply `exit(0)` — a
    /// write that failed during the restore would otherwise leave the user's settings moved and
    /// report success.
    private var harvestHasRun = false
    private var harvestWriteFailures = 0
    private var harvestReadAttempts = 0

    /// Until when the link is taken as up on the strength of a positive event, whatever the
    /// `isConnected()` query says. The query lags several seconds behind an openConnection
    /// that has already returned success — the trace showed it still false through three
    /// deviceDidConnect callbacks — and the refresh that trusted it hid the menu bar item in
    /// the gap. Real evidence of a drop (deviceDidDisconnect) cancels the assertion early.
    private var linkAssertedUntil = Date.distantPast

    /// Covers the observed lag with slack; a wrong assertion self-corrects at the next poll.
    private static let linkAssertionGrace: TimeInterval = 10

    /// When a frame last arrived from the buds.
    ///
    /// This is the one unambiguous signal the app has. `isConnected()` under-reports, and
    /// `deviceDidDisconnect` fires on drops the data stream then carries on straight through
    /// — the trace showed battery and mode reports still landing while both the link and the
    /// channel were believed down. Bytes cannot arrive from earbuds that are not there.
    private var lastFrameAt = Date.distantPast

    /// How long the last frame counts for. The buds push status every few seconds unprompted,
    /// so a gap this long means they have genuinely gone rather than merely fallen quiet.
    private static let frameFreshness: TimeInterval = 8

    /// True while frames are arriving often enough to prove the buds are present.
    private var isStreamLive: Bool { Date().timeIntervalSince(lastFrameAt) < Self.frameFreshness }

    private func assertLinkUp() {
        isConnected = true
        didFailUserConnect = false
        linkAssertedUntil = Date().addingTimeInterval(Self.linkAssertionGrace)
    }
    private var pollTimer: Timer?
    private var ticks = 0

    override init() {
        super.init()
        // A `--selfcheck` or `--render-snapshots` run is a build-time job, not a launch, so
        // nothing here touches the radio — no SDP query, no page attempt, no control channel,
        // no timers poking at the buds while a check is trying to be deterministic.
        if Self.isDetached { return }
        device = Self.discoverDevice()
        syncName()

        // Fires for *any* device connecting; we filter to ours. There is no
        // per-device connect notification in IOBluetooth, only a global one.
        IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:)))

        refreshConnectionState()

        // Two jobs at two rates. Re-reading the link is a local query, so it runs often and
        // keeps `isConnected` honest no matter which notification was missed. Actually
        // reaching for the buds pages the radio, so that only happens every tenth tick.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshConnectionState()
            self.ticks += 1
            if self.ticks % Self.ticksPerConnectAttempt == 0 { self.attemptAutoConnect() }
            // The settings the buds will not push reliably need asking for. Cheap beside the
            // connect attempt and the only thing that keeps the mode honest when the phone is
            // the one changing it.
            if self.ticks % Self.ticksPerStateRefresh == 0 { self.refreshDeviceState() }
        }
        pollTimer?.tolerance = Self.pollInterval / 2   // no deadline worth a forced wakeup
        attemptAutoConnect()
    }

    /// How often the link state is re-read. `isConnected()` is a local lookup, not a radio
    /// round trip, so this can be brisk — it sets how fast the menu bar item reacts to a
    /// case being shut.
    private static let pollInterval: TimeInterval = 2

    /// Connect attempts are the expensive part — a shut case answers with a page timeout —
    /// so they run every tenth poll, i.e. every 20s.
    /// ponytail: fixed interval, not a backoff. Tune these two before adding one.
    private static let ticksPerConnectAttempt = 10

    /// How often the buds are asked for the settings they do not push. Four seconds is well
    /// inside the time it takes to walk over and open the phone's app to compare against it.
    private static let ticksPerStateRefresh = 2

    private func attemptAutoConnect() {
        // Pairing can happen while we are running, so keep looking until something turns up.
        if device == nil {
            device = Self.discoverDevice()
            if device != nil { hasReadDisplayName = false }
        }
        guard !isConnected, !isSwitchedOff, !isBusy else { return }
        connect(auto: true)
    }

    /// Picks the paired device that advertises the `oppointeraction` control service.
    ///
    /// Matching on the service rather than on a hardcoded address means any earbuds
    /// speaking this protocol work, and no one's Bluetooth address ends up in the source.
    /// `BUDSBAR_ADDRESS` forces a specific one when several are paired.
    private static func discoverDevice() -> IOBluetoothDevice? {
        if let forced = ProcessInfo.processInfo.environment["BUDSBAR_ADDRESS"] {
            return IOBluetoothDevice(addressString: forced)
        }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        let uuid = IOBluetoothSDPUUID(bytes: controlServiceUUID, length: 16)
        // Relies on the SDP records cached at pairing time; nothing is paged here.
        return paired.first { $0.getServiceRecord(for: uuid) != nil }
    }

    /// Called at app termination. Releasing the RFCOMM channel matters: macOS grants one
    /// per device, and a channel left to the OS reaper can refuse the next launch its open.
    func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        testTimer?.invalidate()
        testTimer = nil
        disconnectObserver?.unregister()
        disconnectObserver = nil
        closeControlChannel()
    }

    // MARK: - Power toggle

    func connect(auto: Bool = false) {
        guard !isBusy, let device else { return }
        isAutoConnecting = auto
        // Intent is cleared straight away — the user asked for on, so the auto-connect poll
        // must be free to keep retrying. What holds the menu bar item in place across the
        // attempt is `isBusy` being part of `isAvailable`, not this flag.
        isSwitchedOff = false
        isBusy = true
        // Background retries neither surface errors nor erase one the user is reading.
        if !auto { lastError = nil }
        onStateChange?()
        // openConnection blocks until the baseband link is up or times out.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = device.openConnection()
            DispatchQueue.main.async {
                self.isBusy = false
                self.isAutoConnecting = false
                if result == kIOReturnSuccess { self.assertLinkUp() }
                // A failed background attempt is the normal state of a shut case, not an
                // error to display when the item next appears. A failed USER attempt is
                // different: with `isSwitchedOff` already cleared and `isBusy` ending here,
                // every availability term would be false and the item would vanish out from
                // under the toggle the user just flipped. `didFailUserConnect` keeps the item
                // and shows the error while leaving the poll free to retry — parking it in
                // `isSwitchedOff` instead also switched the retry off, so one slow page left
                // the app stuck disconnected until the toggle was used again.
                if result != kIOReturnSuccess, !auto {
                    self.lastError = Self.describe(result)
                    self.didFailUserConnect = true
                }
                // Refresh on both outcomes: a failed attempt still ends `isBusy`, and the
                // status item has to be told, or it sits stale until the next poll.
                self.refreshConnectionState()
            }
        }
    }

    func disconnect() {
        guard !isBusy, let device else { return }
        // The user asked for down — an earlier up-assertion must not outvote them while
        // closeConnection completes.
        linkAssertedUntil = .distantPast
        // Keeps the menu bar item present so the toggle can be switched back on, and stops
        // the auto-connect poll from undoing this a few seconds later.
        isSwitchedOff = true
        // Whatever arrived before this moment no longer counts as evidence of a live link.
        lastFrameAt = .distantPast
        didFailUserConnect = false
        onStateChange?()
        isBusy = true
        closeControlChannel()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = device.closeConnection()
            DispatchQueue.main.async {
                self.isBusy = false
                if result != kIOReturnSuccess { self.lastError = Self.describe(result) }
                self.refreshConnectionState()
            }
        }
    }

    // MARK: - Connection tracking

    /// The one place the disconnect observer is written. Both `deviceDidConnect` and
    /// `refreshConnectionState` need to register it, and assigning over a live registration
    /// leaks it still armed — a later disconnect then fires every orphaned observer too.
    private func armDisconnectObserver(for device: IOBluetoothDevice) {
        disconnectObserver?.unregister()
        disconnectObserver = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDidDisconnect(_:device:)))
    }

    @objc private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device connected: IOBluetoothDevice) {
        guard connected.addressString == device?.addressString else { return }
        // Re-register per connection; the disconnect notification is one-shot.
        armDisconnectObserver(for: connected)
        DispatchQueue.main.async {
            // A link coming back after a switch-off is macOS re-establishing audio for an
            // earbud that is still being worn, not the user asking for the buds back. It is
            // not evidence of intent, so it does not clear `isSwitchedOff` — nor is there any
            // point asserting a link the app has been told to ignore.
            guard !self.isSwitchedOff else { return }
            self.assertLinkUp()
            // Re-read the display name: a new link is the natural moment to notice a rename.
            self.hasReadDisplayName = false
            self.refreshConnectionState()
        }
    }

    @objc private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device disconnected: IOBluetoothDevice) {
        // Fired means spent — it is one-shot — so nil without unregister is correct here.
        disconnectObserver = nil
        DispatchQueue.main.async {
            self.linkAssertedUntil = .distantPast   // a real drop beats any grace window
            self.closeControlChannel()
            self.refreshConnectionState()
        }
    }

    /// Mirrors the name macOS shows in the Bluetooth settings.
    ///
    /// That is not `IOBluetoothDevice.name`, which reports the name the earbuds advertise
    /// over the air — renaming a device in Bluetooth settings does not change what the
    /// hardware calls itself, so the two drift apart (here: "Realme Buds" on screen,
    /// "realme Buds T500 Pro" over the air). Only the Bluetooth daemon holds the display
    /// name; it is in no readable preference file or IORegistry entry, and
    /// `system_profiler` is the one interface that reports it.
    ///
    /// Spawning a process is far too slow for the 2s poll that calls this, so the lookup
    /// runs once in the background and is repeated only when a new link comes up — which
    /// is also when a rename would realistically be noticed. The advertised name stands in
    /// meanwhile, and the hardcoded default only shows before either has answered.
    private func syncName() {
        if name == Self.fallbackName, let advertised = device?.name, !advertised.isEmpty {
            name = advertised
        }

        guard !hasReadDisplayName else { return }
        hasReadDisplayName = true
        guard let address = device?.addressString else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let displayName = Self.displayNameFromSystemProfiler(address: address)
            else { return }
            DispatchQueue.main.async {
                if self.name != displayName {
                    self.name = displayName
                    self.onStateChange?()
                }
            }
        }
    }

    /// Reads the name Bluetooth settings shows. Each device is a single-pair dictionary
    /// keyed by its display name, so the key is the value we want and the address inside
    /// identifies which entry is ours.
    private static func displayNameFromSystemProfiler(address: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Drain before waiting: a full pipe buffer would deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        let wanted = address.replacingOccurrences(of: "-", with: ":").uppercased()
        for section in sections {
            // Look in both lists so the name is right even when the buds are away.
            for listKey in ["device_connected", "device_not_connected"] {
                guard let list = section[listKey] as? [[String: Any]] else { continue }
                for entry in list {
                    for (displayName, raw) in entry {
                        guard let info = raw as? [String: Any],
                              let addr = info["device_address"] as? String,
                              addr.uppercased() == wanted
                        else { continue }
                        return displayName
                    }
                }
            }
        }
        return nil
    }

    func refreshConnectionState() {
        // A detached instance has no device and no radio: this is a check run, a snapshot
        // render, or a fixture capture before the link is up. Re-reading the link state here
        // would compute "false" from a nil device and wipe the state that was just seeded —
        // which is exactly what happened, and made the golden images differ between renders
        // depending on whether `onAppear` had fired yet.
        guard !Self.isDetached else { return }
        syncName()
        // A live stream outranks everything else. `isConnected()` under-reports badly — it
        // goes false while the headset link is plainly still up, because the audio side holds
        // its own reference to a device this process has stopped connecting to — and the
        // assertion grace only papered over that for its ten seconds. Once it lapsed the
        // toggle flipped itself off, auto-connect asserted the link up again, and the two took
        // turns forever. The remaining terms are for the window before the first frame lands.
        //
        // A switch-off beats all of it. Frames keep arriving for a while after
        // `closeConnection` — believing them would put the app straight back into the loop
        // under a new name.
        let connected = !isSwitchedOff
            && (isStreamLive
                || isControlChannelOpen
                || (device?.isConnected() ?? false)
                || Date() < linkAssertedUntil)
        if connected != isConnected {
            FileHandle.standardError.write(Data((
                "LINK connected=\(connected) stream=\(isStreamLive) "
                + "channel=\(isControlChannelOpen) "
                + "available=\(connected || isSwitchedOff)\n").utf8))
        }
        isConnected = connected
        // `isSwitchedOff` is deliberately not touched here. It is user intent, and this
        // method is a state re-read that the poll calls every 2s — clearing the flag on
        // `connected` raced the poll against closeConnection(): the tick landing before the
        // link finished dropping saw connected=true, wiped the just-set flag, and the item
        // vanished once the drop completed. Intent is written only by connect()/disconnect()
        // and by deviceDidConnect (a genuine new link means the buds are on and in use).
        defer { onStateChange?() }
        if connected {
            // The connect notification only fires for connections made while we are running,
            // so buds already connected at launch would never get a disconnect observer —
            // and shutting the case would go unnoticed, leaving the menu bar item on screen.
            if disconnectObserver == nil, let device {
                armDisconnectObserver(for: device)
            }
            openControlChannel()
        } else {
            battery = Battery()
            placement = Placement()
            mode = nil
            ancLevel = nil
            eqPreset = nil
            bassWave = nil
            touchRules = []
            hasCustomEQProfile = nil
            // The firmware string belongs to the connection too: without this, a paired-but-
            // disconnected panel (or one wearing a different device's name) keeps showing the
            // version of buds it is no longer talking to.
            firmware = nil
        }
    }

    // MARK: - Vendor control channel

    private func openControlChannel() {
        // `channel` is not assigned until the async work below finishes, so it cannot on its
        // own tell a second caller that an open is already under way. Without `isOpening`,
        // reopening the panel during those few seconds starts a competing SDP query and a
        // second openRFCOMMChannelAsync, which collide — and every command sent meanwhile is
        // dropped by `send`, which reads as the whole app lagging.
        guard channel == nil, !isOpening, let device else { return }
        isOpening = true

        DispatchQueue.global(qos: .userInitiated).async {
            // SDP-resolve the channel rather than hardcoding 15, so a firmware
            // renumber can't silently point us at a different service. The query has to run
            // in this process at least once or the channel open never completes.
            device.performSDPQuery(nil)

            // Poll instead of sleeping a flat two seconds: the record usually resolves in
            // well under that, and the wait used to be paid in full on every connect.
            let uuid = IOBluetoothSDPUUID(bytes: Self.controlServiceUUID, length: 16)
            var record: IOBluetoothSDPServiceRecord?
            for _ in 0..<40 {
                record = device.getServiceRecord(for: uuid)
                if record != nil { break }
                Thread.sleep(forTimeInterval: 0.05)
            }

            var channelID: BluetoothRFCOMMChannelID = 0
            guard let record else {
                DispatchQueue.main.async {
                    self.isOpening = false
                    // The messages in this file are the ones on screen, so they say what
                    // happened to the user rather than naming the SDP record or the IOReturn
                    // that produced them. The numbers are still in the trace.
                    self.lastError = "Couldn't reach the earbuds' control channel."
                }
                return
            }
            guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
                DispatchQueue.main.async {
                    self.isOpening = false
                    self.lastError = "These earbuds don't offer a control channel."
                }
                return
            }

            DispatchQueue.main.async {
                defer { self.isOpening = false }
                // A switch-off can land while the SDP query above is still in flight. Honour it:
                // opening here would command buds the user just turned off, and `disconnect()`
                // has already decided this channel should not exist. The completion handler has
                // the same guard, for the race it cannot see — a switch-off arriving between this
                // call and its callback.
                guard !self.isSwitchedOff, self.channel == nil else { return }
                var opened: IOBluetoothRFCOMMChannel?
                let result = device.openRFCOMMChannelAsync(
                    &opened, withChannelID: channelID, delegate: self)
                if result == kIOReturnSuccess {
                    self.channel = opened
                } else {
                    // Most likely another host already holds the control channel.
                    self.lastError = "The earbuds' control channel is in use by something "
                        + "else — the phone app, usually."
                }
            }
        }
    }

    private func closeControlChannel() {
        channel?.close()
        channel = nil
        rxBuffer.removeAll()
        isControlChannelOpen = false
    }

    // MARK: - Noise control

    func set(mode requested: NoiseMode) {
        // The mask carries both, and the level is the same field, so switching to Noise
        // cancellation has to name one. Reusing the level the buds last reported is what makes
        // the button a no-op for someone who has already chosen one on the phone.
        let level = requested == .noiseCancellation ? (ancLevel ?? .high) : nil
        send(BudsProtocol.encodeSetNoiseMask(level?.mask ?? requested.mask))
        refreshAfterSet()
        // `mode` is deliberately left alone: the buds are asked to read it back and the
        // readback is what the UI renders, so this panel and the phone cannot disagree.
    }

    func set(ancLevel requested: ANCLevel) {
        send(BudsProtocol.encodeSetNoiseMask(requested.mask))
        refreshAfterSet()
    }

    func set(eqPreset requested: EQPreset) {
        // Client-side validation, because the firmware has none: it accepts 0x00–0x07 and
        // stores whatever it is given, and a stored out-of-range preset leaves the phone's own
        // UI showing no selection at all.
        send(BudsProtocol.encodeSetEQPreset(requested))
        refreshAfterSet()
    }

    func set(bassWave level: Int) {
        send(BudsProtocol.encodeSetBassWave(level))
        refreshAfterSet()
    }

    /// Rings the given buds.
    func find(_ slots: [BudsProtocol.BatterySlot] = [.left, .right]) {
        send(BudsProtocol.encodeFind(slots))
    }

    /// Asks the buds to end a tone that `find` started.
    ///
    /// The vendor app only ever rings: the corpus has no stop frame, and the setter is answered
    /// with a bare result byte whether or not a tone is playing, so no capture can confirm a
    /// stop. This re-uses the allowlisted find setter with an empty slot list — the same request
    /// as "ring nothing" — and the UI words it as a request, not as a fact, because whether the
    /// firmware honours it can only be settled by ear.
    func stopFind() {
        send(BudsProtocol.encodeFind([]))
    }

    /// What a gesture currently does, taken from the left earbud. The phone keeps the two in
    /// step, so the left is the row the UI shows and the one it writes back to both.
    func touchAction(_ gesture: BudsProtocol.MediaGesture) -> BudsProtocol.GestureAction? {
        touchRules.first {
            $0.side == BudsProtocol.TouchRule.left
                && $0.type == BudsProtocol.TouchRule.media
                && $0.gesture == gesture.rawValue
        }.flatMap { BudsProtocol.GestureAction(rawValue: $0.action) }
    }

    /// Re-points one gesture on **both** earbuds.
    ///
    /// Only the two changed records are sent, so a byte mis-read anywhere else in the table
    /// cannot be written back, and the two sides cannot drift apart — which is exactly the
    /// state the phone's screen cannot represent.
    func setTouch(gesture: BudsProtocol.MediaGesture, action: BudsProtocol.GestureAction) {
        let rules = [BudsProtocol.TouchRule.left, BudsProtocol.TouchRule.right].map {
            BudsProtocol.TouchRule(side: $0, type: BudsProtocol.TouchRule.media,
                                   gesture: gesture.rawValue, action: action.rawValue)
        }
        send(BudsProtocol.encodeSetTouch(rules))
        // The table is read back rather than assumed: the firmware acknowledges the write long
        // before it takes effect, and the round trip is what the row renders.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isControlChannelOpen else { return }
            self.send(BudsProtocol.encodeRequest(.touch))
        }
    }

    @discardableResult
    private func send(_ packet: [UInt8]) -> Bool {
        guard let channel, isControlChannelOpen else { return false }
        // `writeAsync` takes a `UInt16` length and a protocol frame is tens of bytes, but the
        // conversion traps rather than truncating, so a caller that ever exceeded it would take
        // the process down instead of getting the `false` every other failure returns.
        guard packet.count <= Int(UInt16.max) else {
            lastError = "That command is too large to send."
            return false
        }
        var bytes = packet
        let result = bytes.withUnsafeMutableBytes { raw in
            channel.writeAsync(raw.baseAddress, length: UInt16(raw.count), refcon: nil)
        }
        if result != kIOReturnSuccess {
            lastError = "Couldn't send a command to the earbuds."
            return false
        }
        // A command going out is proof the condition behind a write error has passed: the
        // channel is up and taking writes. Without this, one transient `writeAsync` failure
        // left its row on both surfaces until a non-auto connect or a fresh channel open, long
        // after the link had recovered.
        lastError = nil
        return true
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            lastError = "Couldn't open the earbuds' control channel."
            self.channel = nil
            return
        }
        // The switch-off raced the open. Close rather than handshake: the handshake is a write, and
        // writing to buds the user just turned off is the one thing the switch exists to prevent.
        // `closeControlChannel` has already decided this channel should not exist; this undoes the
        // part of the open that was already in flight when it did.
        if isSwitchedOff {
            channel?.close()
            self.channel = nil
            isControlChannelOpen = false
            return
        }
        isControlChannelOpen = true
        lastError = nil
        if ProcessInfo.processInfo.environment["BUDSBAR_TEST"] != nil {
            // Give the handshake sent below time to land first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.startModeTest() }
        }
        for packet in BudsProtocol.handshake() {
            var bytes = packet
            _ = bytes.withUnsafeMutableBytes { raw in
                channel.writeAsync(raw.baseAddress, length: UInt16(raw.count), refcon: nil)
            }
        }
        // A fresh connection knows nothing: the buds do not push their settings on their own,
        // so everything the panel shows is asked for once the channel is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.isControlChannelOpen else { return }
            self.refreshDeviceState()
            self.readAudioSettings()
        }
        if Self.isHarvesting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.runHarvest() }
        }
    }

    /// Walks every mode, level, EQ preset, and BassWave step, then restores what it found, so a
    /// raw capture taken alongside contains one clean example of every frame type.
    ///
    /// This is the recon workflow, kept in the app rather than in a throwaway hook: it is the
    /// only way to obtain fixtures that are internally consistent, and it matters that it is
    /// reproducible, because the alternative — transcribing bytes by hand — has already
    /// produced fixtures whose length fields disagree with their own payloads.
    ///
    /// It writes to the buds, so it puts them back: the values restored are the ones the
    /// handshake and first poll read off them a moment ago, not a fixed "off / balanced / 0",
    /// which would silently move a user's settings. It runs only under `BUDSBAR_HARVEST=1`,
    /// and the poll is suspended for the duration so the capture is not interleaved with it.
    private func runHarvest() {
        // Scheduled from every channel open, so a reconnect mid-sweep would otherwise start a
        // second sweep on top of the first, with two restore sequences interleaved.
        guard !harvestHasRun else { return }

        // Nothing is moved until the buds have actually been read. The sweep writes, and its
        // restore replays what it found — with no readings, "what it found" is nil and the
        // restore writes off / balanced / 0, silently moving the user's settings. That is
        // precisely what it must not do, so wait for the first poll. Bounded, so buds that never
        // answer cannot spin here forever.
        if mode == nil, ancLevel == nil, eqPreset == nil, bassWave == nil {
            harvestReadAttempts += 1
            guard harvestReadAttempts <= 10 else {
                testLog("HARVEST aborted: the buds have not answered, so there is nothing to restore")
                exit(2)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.runHarvest() }
            return
        }
        harvestHasRun = true

        let readANC = BudsProtocol.encodeRequest(.anc, payload: [0x01, 0x01])
        let readEQ = BudsProtocol.encodeRequest(.eqPreset)
        let readBass = BudsProtocol.encodeRequest(.bassWave)

        // What was found, for the restore at the end.
        let priorMode = mode
        let priorLevel = ancLevel
        let priorEQ = eqPreset
        let priorBass = bassWave
        testLog("HARVEST found mode=\(priorMode.map { "\($0.mask)" } ?? "-") "
                + "level=\(priorLevel.map { "\($0.mask)" } ?? "-") "
                + "eq=\(priorEQ.map { "\($0.rawValue)" } ?? "-") "
                + "bass=\(priorBass.map(String.init) ?? "-")")

        var steps: [(String, [UInt8])] = []
        for mode in NoiseMode.allCases {
            steps.append(("set \(mode.label) 0x\(String(format: "%04x", mode.mask))",
                          BudsProtocol.encodeSetNoiseMask(mode.mask)))
            steps.append(("read anc", readANC))
        }
        for level in ANCLevel.allCases {
            steps.append(("set nc \(level.label) 0x\(String(format: "%04x", level.mask))",
                          BudsProtocol.encodeSetNoiseMask(level.mask)))
            steps.append(("read anc", readANC))
        }
        steps += [
            ("set eq bass", BudsProtocol.encodeSetEQPreset(.bass)),
            ("read eq", readEQ),
            ("set eq balanced", BudsProtocol.encodeSetEQPreset(.balanced)),
            ("read eq", readEQ),
            ("set basswave +2", BudsProtocol.encodeSetBassWave(2)),
            ("read basswave", readBass),
            ("set basswave 0", BudsProtocol.encodeSetBassWave(0)),
            ("read basswave", readBass),
            ("read custom eq", BudsProtocol.encodeRequest(.customEQ)),
            ("read touch", BudsProtocol.encodeRequest(.touch)),
        ]

        // Put the buds back the way they were found. ANC last, so the capture's final state
        // matches the first line of this function's log.
        let restoreMask = priorLevel.map { $0.mask }
            ?? priorMode?.mask
            ?? NoiseMode.off.mask
        steps += [
            ("restore basswave \(priorBass.map(String.init) ?? "0")",
             BudsProtocol.encodeSetBassWave(priorBass ?? 0)),
            ("restore eq \(priorEQ?.label ?? "balanced")",
             BudsProtocol.encodeSetEQPreset(priorEQ ?? .balanced)),
            ("restore anc 0x\(String(format: "%04x", restoreMask))",
             BudsProtocol.encodeSetNoiseMask(restoreMask)),
            ("read anc", readANC),
        ]

        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(index) * 2.0) {
                self.testLog("HARVEST \(step.0) :: \(BudsProtocol.hex(step.1))")
                // A failed write is not cosmetic here: the closing steps put the buds back the
                // way they were found, and a sweep that cannot write has left the user's settings
                // moved. Count them rather than exiting as if it worked.
                if !self.send(step.1) { self.harvestWriteFailures += 1 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(steps.count) * 2.0 + 2) {
            guard self.harvestWriteFailures == 0 else {
                self.testLog("HARVEST failed: \(self.harvestWriteFailures) writes did not go out, so the "
                             + "buds may be left in the last state the sweep wrote — restore by hand")
                exit(1)
            }
            self.testLog("HARVEST done")
            exit(0)
        }
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let chunk = Array(UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))

        // The buds go on talking for a while after a switch-off, and acting on that would
        // walk the app back to connected against the user's wishes. Drop it on the floor,
        // buffer included, so nothing is half-parsed when the toggle comes back on.
        guard !isSwitchedOff else {
            rxBuffer.removeAll()
            return
        }

        // Data is the proof the channel is alive, whatever the link bookkeeping believes. A
        // spurious deviceDidDisconnect tears the channel down on paper while the real one
        // keeps delivering; without this the app sat deaf behind that teardown, showing
        // Disconnected and a dead noise-control card while battery reports rolled in.
        lastFrameAt = Date()
        if !isControlChannelOpen {
            isControlChannelOpen = true
            self.channel = channel
            refreshConnectionState()
        }

        rxBuffer.append(contentsOf: chunk)

        // RFCOMM delivers arbitrary chunks; frames split across callbacks.
        let frames = BudsProtocol.drainFrames(from: &rxBuffer)
        // Raw trace, for decoding payloads that are still unknown and for capturing fixtures.
        // Both forms: the bytes verbatim, so a capture can be replayed, and the decode, so a
        // human can read it. Opt-in — the buds push status every few seconds.
        if Self.isTracing {
            for frame in frames {
                FileHandle.standardError.write(Data(
                    ("RX " + BudsProtocol.hex(frame.raw) + "   |   "
                     + BudsProtocol.describe(frame) + "\n").utf8))
            }
        }
        for frame in frames { apply(frame) }
    }

    // MARK: - Reading state

    /// Re-reads the settings the firmware does not reliably push.
    ///
    /// ANC is the important one: the push that carries it is lossy on this hardware (the low
    /// byte alone, which cannot tell Transparency from Adaptive), and *no* push arrived at all
    /// for our own writes in testing. Without this poll the panel would keep showing whatever
    /// was last commanded, or whatever the phone changed minutes ago.
    private func refreshDeviceState() {
        guard isControlChannelOpen else { return }
        // Suppressed during a fixture capture: the periodic readbacks would interleave with
        // the scripted sequence and make the capture harder to read than it needs to be.
        guard !Self.isHarvesting else { return }
        for packet in [
            BudsProtocol.encodeRequest(.anc, payload: [0x01, 0x01]),
            BudsProtocol.encodeRequest(.battery),
            BudsProtocol.encodeRequest(.wear),
        ] { send(packet) }
    }

    /// The audio settings, which change only when asked to, plus the firmware string and the
    /// gesture table. Read once per connection and once after each write.
    private func readAudioSettings() {
        guard isControlChannelOpen else { return }
        for packet in [
            BudsProtocol.encodeRequest(.eqPreset),
            BudsProtocol.encodeRequest(.bassWave),
            BudsProtocol.encodeRequest(.customEQ),
            BudsProtocol.encodeRequest(.firmware),
            BudsProtocol.encodeRequest(.touch),
        ] { send(packet) }
    }

    /// A write is acknowledged long before it is reflected, so the readback is deferred. Both
    /// are also covered by the poll; this only makes the panel feel immediate.
    private func refreshAfterSet() {
        for delay in [0.35, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isControlChannelOpen else { return }
                self.refreshDeviceState()
                self.readAudioSettings()
            }
        }
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        closeControlChannel()
    }

    private func apply(_ frame: BudsProtocol.Frame) {
        // Two replies do not fit the counted update shape and are decoded on their own.
        if let version = BudsProtocol.firmware(from: frame) {
            if firmware != version { firmware = version }
            return
        }
        if let rules = BudsProtocol.touchRules(from: frame) {
            if touchRules != rules { touchRules = rules }
            return
        }
        // The custom-EQ reply is a whole profile table when one exists and a bare `00 00`
        // when none does. Only the first byte past the status is needed to know which: the
        // profile editor itself is out of scope, but the preset picker has to know whether
        // the custom slot is selectable at all.
        if frame.cmd == BudsProtocol.Command.customEQ.rawValue,
           frame.messageType == BudsProtocol.MessageType.reply.rawValue {
            hasCustomEQProfile = frame.payload.count >= 2 && frame.payload[1] > 0
            return
        }
        for update in BudsProtocol.interpret(frame) { apply(update) }
        // The same bodies come back as replies to our own requests, one status byte longer.
        for update in BudsProtocol.decode(reply: frame) { apply(update) }
    }

    private func apply(_ update: BudsProtocol.Update) {
        switch update {
        case .eqPreset(let value):
            eqPreset = value
        case .bassWave(let value):
            bassWave = value
        case .noiseMode(let value):
            if mode != value {
                decodeLog("MODE reported \(value.label) 0x\(String(format: "%04x", value.mask))")
            }
            mode = value
        case .ancLevel(let value):
            if ancLevel != value {
                decodeLog("LEVEL reported \(value.label)")
            }
            ancLevel = value
        case .battery(let slot, let level):
            // Assigned, not merged: nil here means the buds reported the slot as
            // unknown, and a slot they did not mention produces no update at all.
            switch slot {
            case .left: battery.left = level
            case .right: battery.right = level
            case .enclosure: battery.enclosure = level
            }

        case .placement(let slot, let where_):
            guard placement[slot] != where_ else { break }
            decodeLog("PLACEMENT \(slot) \(where_)")
            placement[slot] = where_
            // Only on the move out of use, not on every report of it. A bud put away
            // drops out of the battery report entirely, and an absent slot keeps its last
            // reading — so the reading it had while in use would stand on the panel
            // indefinitely. Clearing it once is enough: an awake case goes on reporting
            // the bud inside it, and the next report fills the value back in within
            // seconds. A case that has gone to sleep reports nothing, which is when the
            // stale number used to sit there, and now the cell honestly reads unknown.
            // `.notPresent` counts as out of use too: the slot is decodable but was never
            // seen on hardware, so a bud that goes absent must not keep a full-strength
            // reading feeding the headline.
            if !where_.isUsable {
                switch slot {
                case .left: battery.left = nil
                case .right: battery.right = nil
                case .enclosure: break
                }
            }
        }
    }

    // MARK: - Mode cycle test

    /// Drives every mode and every ANC level in turn so the commands can be verified end to
    /// end against the notifications the buds send back. Runs only under BUDSBAR_TEST=1.
    private var testQueue: [(label: String, send: () -> Void)] = []
    private var testTimer: Timer?

    private func startModeTest() {
        guard isControlChannelOpen else { return }
        testQueue = NoiseMode.allCases.map { mode in
            ("\(mode.label) 0x\(String(format: "%04x", mode.mask))",
             { [weak self] in self?.set(mode: mode) })
        } + ANCLevel.allCases.map { level in
            ("ANC \(level.label) 0x\(String(format: "%04x", level.mask))",
             { [weak self] in self?.set(ancLevel: level) })
        }
        testLog("cycling modes, 3s apart")
        testTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let next = self.testQueue.first else {
                self.testLog("mode cycle complete")
                self.testTimer?.invalidate()
                self.testTimer = nil
                return
            }
            self.testQueue.removeFirst()
            self.testLog("commanding \(next.label)")
            next.send()
        }
    }

    private func testLog(_ message: String) {
        FileHandle.standardError.write(Data("TEST \(message)\n".utf8))
    }

    /// Live decode trace for a change in mode, level or placement.
    ///
    /// Silent in a check, a snapshot render or a test run: those replay the fixture corpus
    /// through these same decoders, and the lines would read as a wall of errors in a passing
    /// test log. Not gated on `isTracing` because these three are the changes a person is
    /// usually looking for when they ask for the trace.
    private func decodeLog(_ message: String) {
        guard !Self.isDetached else { return }
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    // MARK: - Snapshots

    /// The states the snapshot renderer draws. Not every state a live session can be in —
    /// just the ones that are worth a picture, which is to say the ones whose layout is not
    /// obvious and could silently break.
    enum SnapshotState {
        /// Link up, everything read: the steady state.
        case connected
        /// Link up but the control channel is not open yet, so nothing has been read. This is
        /// the state a person sees for the first second or two after the buds connect, and
        /// the one that is easiest to leave full of empty boxes and dashes that read as
        /// faults. It is rendered on purpose rather than assumed to be fine.
        case warmingUp
        /// Paired, and the link is down: the buds are off, or asleep in a closed case. This is the
        /// state a person looks at most of the time, and it has no readings at all — so it is the
        /// one where the surface has to explain itself rather than draw empty boxes that read as
        /// faults.
        case disconnected
    }

    /// Fills in the state a live session would have produced, for the snapshot renderer.
    ///
    /// The values are the decoded captures from `FixtureCorpus`, fed through the very same
    /// `apply(_ frame:)` the radio goes through — not invented numbers. So a golden image
    /// shows what this app draws against this unit, and a decoder change that altered what
    /// the corpus means would change the images with it rather than leaving them stale.
    func seedForSnapshot(_ state: SnapshotState = .connected) {
        name = Buds.fallbackName
        // A live session is always paired, connected or not. Without this the renderer draws a
        // state the app cannot be in — connected but "Not paired" — and the power button comes out
        // disabled on a fully-connected panel.
        isPairedOverride = true
        // Nothing is fabricated in any state. The corpus defines the connected state; the others
        // are defined by what is *absent*, which is the part worth pinning.
        isConnected = state != .disconnected
        guard state == .connected else { return }
        isControlChannelOpen = true
        for capture in FixtureCorpus.frames {
            var buffer = capture.bytes
            for frame in BudsProtocol.drainFrames(from: &buffer) { apply(frame) }
        }
        // Nothing is invented on top of the replay. The corpus is the state, and if a capture
        // ever stopped yielding one of these readings, the UI's own not-yet-read treatment is
        // what should show — a fabricated default would be a claim the buds never made.
    }

    // MARK: - Errors

    private static func describe(_ code: IOReturn) -> String {
        switch code {
        case kIOReturnSuccess: return "ok"
        case kIOReturnTimeout: return "timed out — buds asleep, in the case, or out of range"
        case kIOReturnNoDevice: return "device not found"
        case kIOReturnBusy: return "busy"
        case kIOReturnExclusiveAccess: return "already in use by another app"
        case kIOReturnNotOpen: return "not open"
        default: return "IOReturn \(code)"
        }
    }
}

extension BudsProtocol.BudPlacement {
    /// False for a bud that is stowed in the case or gone absent: neither is a bud *in use*,
    /// so its chip is dimmed and its last battery reading is dropped rather than feeding the
    /// headline as though the bud were still in an ear. `.notPresent` (0x00) is decodable but
    /// was never observed on this hardware, so it is folded in with `.inCase` defensively
    /// rather than guessed into a fourth behaviour. Used by the model — which clears the
    /// reading — and by `BatteryChip`, which dims it, so the two cannot disagree.
    var isUsable: Bool { self == .inEar || self == .outOfCase }
}
