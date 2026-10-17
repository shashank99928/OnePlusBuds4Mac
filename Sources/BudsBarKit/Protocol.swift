import Foundation
import os

// MARK: - Noise control

/// A noise-control mode, as the firmware reports and accepts it: one 16-bit mask value.
///
/// The mode is *not* a small enum on the wire. Off, the four cancellation levels, both
/// passthrough modes and Adaptive all live in one bitfield, and the level is not a separate
/// field — it *is* the value.
///
/// An earlier version of this file read that field as a single byte and mapped `0x02` to
/// Transparency and `0x08` to "Max ANC". Measured against the hardware with `Tools/sniff.swift`,
/// those bytes command *Noise cancellation* and *Off* respectively, so two of the three
/// buttons sent a different mode than they claimed. The values below were each set and read
/// back one at a time.
enum NoiseMode: String, CaseIterable, Identifiable {
    case noiseCancellation
    case adaptive
    case transparency
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noiseCancellation: return "Noise cancellation"
        case .adaptive: return "Adaptive"
        case .transparency: return "Transparency"
        case .off: return "Off"
        }
    }

    /// Audio metaphors, not people: a crossed-out waveform for cancellation, a magnifier over
    /// a waveform for Adaptive, an ear for hearing your surroundings, the universal off mark.
    ///
    /// Adaptive used to be `waveform.badge.ellipsis`, which does not exist — SwiftUI draws
    /// nothing at all for an unknown symbol, so the pill rendered with a blank where its
    /// icon should be, and nothing failed. Every name here is checked against the running OS
    /// by `Tools/check-symbols.swift`.
    var symbol: String {
        switch self {
        case .noiseCancellation: return "waveform.slash"
        case .adaptive: return "waveform.badge.magnifyingglass"
        case .transparency: return "ear"
        case .off: return "circle.slash"
        }
    }

    /// The mask the firmware stores for this mode. Noise cancellation is reported at
    /// whichever level it is on, so this is its High level — the same default the phone
    /// sends; `ANCLevel` carries the rest.
    var mask: UInt16 {
        switch self {
        case .noiseCancellation: return ANCLevel.high.mask
        case .adaptive: return 0x0800
        case .transparency: return 0x0100
        case .off: return 0x0008
        }
    }

    /// nil for a value this app does not model — a mask from a newer firmware, or the
    /// low byte of a lossy push with the high byte missing.
    init?(mask: UInt16) {
        switch mask {
        case 0x0008: self = .off
        case 0x0100: self = .transparency
        case 0x0800: self = .adaptive
        case 0x0010, 0x0020, 0x0040, 0x0080: self = .noiseCancellation
        default: return nil
        }
    }
}

/// How hard cancellation works while it is on.
///
/// The values are not in strength order and are not guessable: High is `0x0010`,
/// Moderate `0x0020`, Low `0x0040`, Auto `0x0080`. Each was set and read back in turn.
///
/// Declared strongest-first, matching the phone's own order — `allCases` is what the
/// picker renders, and it is deliberately not the wire order.
enum ANCLevel: String, CaseIterable, Identifiable {
    case high
    case moderate
    case low
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: return "High"
        case .moderate: return "Moderate"
        case .low: return "Low"
        case .auto: return "Auto"
        }
    }

    var detail: String {
        switch self {
        case .high: return "Very noisy places — planes and trains"
        case .moderate: return "Noisy places — streets and malls"
        case .low: return "Quieter places — home and office"
        case .auto: return "The buds pick a level as your surroundings change"
        }
    }

    var mask: UInt16 {
        switch self {
        case .high: return 0x0010
        case .moderate: return 0x0020
        case .low: return 0x0040
        case .auto: return 0x0080
        }
    }

    init?(mask: UInt16) {
        switch mask {
        case 0x0010: self = .high
        case 0x0020: self = .moderate
        case 0x0040: self = .low
        case 0x0080: self = .auto
        default: return nil
        }
    }
}

/// Sound Master EQ presets.
///
/// The Buds 4 ships three and a slot for one saved custom profile. `0x03` is skipped by the
/// firmware entirely, and `0x04` is the custom slot — which cannot be selected until a
/// profile exists, so the UI offers it only when `Buds.customEQ` says one does.
enum EQPreset: String, CaseIterable, Identifiable {
    case balanced
    case clearVocals
    case bass
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .clearVocals: return "Clear Vocals"
        case .bass: return "Bass"
        case .custom: return "Custom"
        }
    }

    var value: UInt8 {
        switch self {
        case .balanced: return 0x00
        case .clearVocals: return 0x01
        case .bass: return 0x02
        case .custom: return 0x04
        }
    }

    init?(value: UInt8) {
        switch value {
        case 0x00: self = .balanced
        case 0x01: self = .clearVocals
        case 0x02: self = .bass
        case 0x04: self = .custom
        default: return nil
        }
    }
}

/// Wire format for the `oppointeraction` RFCOMM channel on OnePlus / OPPO / realme earbuds.
///
/// Pure functions over bytes — no I/O — so `selfCheck()` can exercise them against captured
/// traffic without the hardware present.
///
///     aa <len:varint> 00 00 <cmd> <msgType> <seq> <payloadLen:u16le> <payload…>
///
/// `len` is a base-128 varint counting every byte after itself, so a frame is
/// `1 + len(varint) + len` bytes. There is no checksum: the two length fields are the only
/// integrity check, and agreeing on both is what tells a real frame from a stray sync byte.
enum BudsProtocol {

    static let sync: UInt8 = 0xaa

    /// Byte 5 of a frame. Byte 4 is the command and byte 5 the message type — *not* one
    /// little-endian 16-bit code, which mis-reads REGISTER (`00 85`) as "command 0x8500".
    /// The `0x0404`-style labels used in the reverse-engineering write-ups are just
    /// `(messageType << 8) | cmd`.
    enum MessageType: UInt8 {
        case request = 0x01
        case notification = 0x02
        case set = 0x04
        /// A settings push. The command byte names the subject using its *own* numbering,
        /// which does not match the getter ids — see `Command`.
        case stateChange = 0x05
        case reply = 0x81
        case setAck = 0x84
        case register = 0x85
    }

    /// Getter command ids, as used in requests and replies.
    enum Command: UInt8 {
        case firmware = 0x05
        case battery = 0x06
        case touch = 0x08
        case wear = 0x09
        case anc = 0x0c
        case miscConfig = 0x0d
        case eqPreset = 0x0f
        case connectedDevices = 0x12
        case customEQ = 0x22
        case bassWave = 0x24
        case capabilities = 0x2f
    }

    /// Setter command ids. A **different namespace**, confirmed against the hardware: the EQ
    /// preset setter happens to match its getter (`0x06`), but BassWave's is `0x1B` against a
    /// getter of `0x24`, and touch's is `0x01` against `0x08`. Deriving one from the other
    /// looks plausible and simply does nothing — the firmware would not even acknowledge the
    /// wrong id in the one case tested.
    enum Setter: UInt8 {
        case find = 0x00
        case touch = 0x01
        case anc = 0x04
        case eqPreset = 0x06
        case bassWave = 0x1b
    }

    struct Frame {
        /// Byte 4: which subject.
        var cmd: UInt8
        /// Byte 5: request / reply / set / notification.
        var messageType: UInt8
        var sequence: UInt8
        var payload: [UInt8]
        var raw: [UInt8]

        /// `(messageType << 8) | cmd`, the label the protocol write-ups use.
        var opcode: UInt16 { UInt16(messageType) << 8 | UInt16(cmd) }

        /// Unsolicited status push. Family 1 of the three notification families: the command
        /// byte is `0x04` and the type is `0x02`, and `payload[0]` selects the topic.
        ///
        /// This used to require the command byte to be `0x0c`, from the ANC getter's id. The
        /// one family-1 frame this unit actually sends unprompted — the connected-device
        /// table — carries `0x04`, so the test rejected the only real example it had and every
        /// status push was silently ignored.
        var isStatusNotification: Bool {
            cmd == BudsProtocol.statusNotificationCommand
                && messageType == MessageType.notification.rawValue
        }
    }

    /// Byte 4 of a family-1 notification. Shared by set-ANC and family-2 pushes, which are
    /// told apart by the message type rather than by this byte.
    static let statusNotificationCommand: UInt8 = 0x04

    enum Update: Equatable {
        case noiseMode(NoiseMode)
        case ancLevel(ANCLevel)
        /// One slot at a time, and nil means "reported as unknown" — not "absent".
        ///
        /// A battery frame can carry a subset of the three slots, so a slot that is missing
        /// must keep its last value while a slot that is present but unreadable must be
        /// cleared. Bundling all three into one update collapsed those two cases together,
        /// and a case that had gone to sleep kept showing its last percentage forever.
        case battery(BatterySlot, Int?)
        /// Where one bud is. Only emitted for values `BudPlacement` recognises.
        case placement(BatterySlot, BudPlacement)
        case eqPreset(EQPreset)
        /// The BassWave level, −5…+5.
        case bassWave(Int)
    }

    enum BatterySlot: UInt8 {
        case left = 0x01
        case right = 0x02
        case enclosure = 0x03
    }

    /// Where a bud is, decoded from the wear flags.
    ///
    /// These are bit flags, measured by moving the buds between an ear, a hand and the case:
    /// `0x01` = out of the case, `0x02` = in an ear, `0x04` = present at all. Only the three
    /// combinations actually observed are modelled; anything else falls out of
    /// `init?(rawValue:)` rather than being guessed into a state.
    ///
    /// This is what stops a bud charging in the case from being drawn as one in use, and it
    /// covers a gap in the battery report: a bud in the case drops out of that report
    /// entirely rather than reporting as unknown.
    enum BudPlacement: UInt8 {
        case notPresent = 0x00
        case inCase = 0x04
        /// Out of the case but not in an ear — being held, or worn on a cord.
        case outOfCase = 0x05
        case inEar = 0x07

        var isStowed: Bool { self == .inCase }
        var isWorn: Bool { self == .inEar }
    }

    /// One row of the touch-gesture table.
    ///
    /// `type` is the context (`0x01` when not on a call, `0x06` during one) and `gesture` the
    /// physical action. The two are packed as a little-endian pair by the rest of the family
    /// — `0x0201` is "double tap in the media context", i.e. `type 01, gesture 02`.
    struct TouchRule: Equatable {
        var side: UInt8
        var type: UInt8
        var gesture: UInt8
        var action: UInt8

        static let left: UInt8 = 0x01
        static let right: UInt8 = 0x02
        static let media: UInt8 = 0x01
    }

    /// The gestures the phone's "Earbud controls" screen offers.
    ///
    /// The codes are the `gesture` byte in the media context; `type` is always
    /// `TouchRule.media`. The in-call context (`type 0x06`) is deliberately absent — its two
    /// codes are unnamed in every published description of this protocol and both this unit
    /// and the reference unit store values for them that nothing documents. Guessing between
    /// "answer" and "decline" and writing the guess to the buds risks ending someone's call,
    /// which is not worth the feature.
    enum MediaGesture: UInt8, CaseIterable, Identifiable {
        case doubleTap = 0x02
        case tripleTap = 0x03
        case touchAndHold = 0x04
        case slide = 0x05

        var id: UInt8 { rawValue }

        var label: String {
            switch self {
            case .doubleTap: return "Double tap"
            case .tripleTap: return "Triple tap"
            case .touchAndHold: return "Touch and hold"
            case .slide: return "Slide"
            }
        }

        var symbol: String {
            switch self {
            case .doubleTap: return "hand.tap"
            case .tripleTap: return "hand.tap.fill"
            case .touchAndHold: return "hand.point.up.left"
            case .slide: return "hand.draw"
            }
        }

        /// What the phone offers for this gesture. The firmware validates nothing — it stores
        /// whatever it is sent, and a value outside the phone's own list leaves its UI with no
        /// selection at all — so the list is enforced here instead, exactly as with the EQ
        /// preset.
        ///
        /// Every code below was read off the reference hardware: they are the actions this app
        /// has actually seen stored, not a guess at the rest of the space.
        var actions: [GestureAction] {
            switch self {
            case .doubleTap, .tripleTap:
                return [.none, .playPause, .next, .previous, .voiceAssistant]
            case .touchAndHold:
                return [.none, .noiseControl, .voiceAssistant]
            case .slide:
                return [.none, .volumeControl]
            }
        }
    }

    /// What a gesture points at.
    enum GestureAction: UInt8, CaseIterable, Identifiable {
        case none = 0x00
        case playPause = 0x01
        case voiceAssistant = 0x03
        case previous = 0x05
        case next = 0x06
        case volumeControl = 0x07
        case noiseControl = 0x08

        var id: UInt8 { rawValue }

        var label: String {
            switch self {
            case .none: return "Do nothing"
            case .playPause: return "Play / pause"
            case .voiceAssistant: return "Voice assistant"
            case .previous: return "Previous track"
            case .next: return "Next track"
            case .volumeControl: return "Volume control"
            // "Noise control" collides with the section heading of the same name, and in a
            // menu of *actions* it reads as a destination rather than a verb. The gesture
            // cycles the mode; the label says so.
            case .noiseControl: return "Toggle noise control"
            }
        }

        var symbol: String {
            switch self {
            case .none: return "minus"
            case .playPause: return "playpause"
            case .voiceAssistant: return "mic"
            case .previous: return "backward.end.fill"
            case .next: return "forward.end.fill"
            case .volumeControl: return "speaker.wave.2"
            case .noiseControl: return "waveform.slash"
            }
        }
    }

    /// Entry id carrying the noise mode inside a `noiseMode` payload.
    private static let noiseModeID: UInt8 = 0x01

    // MARK: - Sending

    /// Packets to send once the channel opens. Status arrives unprompted, but OPOv1 expects
    /// a hello before it will accept commands.
    static func handshake() -> [[UInt8]] { [encodeHello()] }

    /// Builds a frame. `len` is a base-128 varint counting every byte after itself, so it
    /// covers the seven remaining header bytes plus the payload.
    ///
    /// The single-byte reading this replaced agrees with it for every frame under 128 bytes —
    /// which is all of them today — and mis-frames anything larger, silently: the length then
    /// predicts a short frame, the payload-length cross-check fails on the real one, and the
    /// whole thing is discarded as resynchronisation noise.
    static func makeFrame(_ b2: UInt8, _ b3: UInt8, cmd: UInt8, messageType: UInt8,
                          sequence: UInt8, payload: [UInt8]) -> [UInt8] {
        precondition(payload.count <= 0xffff, "payload length is a 16-bit field")
        var frame: [UInt8] = [sync]
        frame += encodeVarint(7 + payload.count)
        frame += [b2, b3, cmd, messageType, sequence,
                  UInt8(payload.count & 0xff), UInt8(payload.count >> 8)]
        frame += payload
        return frame
    }

    /// LEB128, little-endian — seven bits per byte, continuation bit high.
    static func encodeVarint(_ value: Int) -> [UInt8] {
        var remaining = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining > 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining > 0
        return out
    }

    /// Decodes a varint.
    ///
    /// nil means the value is not a value: either the bytes ran out mid-value, or the pattern is
    /// longer than any legitimate varint (five bytes is the maximum here). Those two need
    /// opposite handling — one is a short read to wait on, the other is a bad byte to step over —
    /// so the caller tells them apart from the bytes rather than from this result.
    static func decodeVarint<C: Collection>(_ bytes: C) -> (value: Int, length: Int)?
    where C.Element == UInt8 {
        var value = 0, shift = 0, length = 0
        for byte in bytes {
            value |= Int(byte & 0x7f) << shift
            length += 1
            if byte & 0x80 == 0 { return (value, length) }
            shift += 7
            if shift > 28 { return nil }   // nothing legitimate is this long
        }
        return nil
    }

    /// A getter: message type `0x01`, with `cmd` naming the subject.
    static func encodeRequest(_ cmd: Command, payload: [UInt8] = []) -> [UInt8] {
        makeFrame(0x00, 0x00, cmd: cmd.rawValue, messageType: MessageType.request.rawValue,
                  sequence: nextSequence(), payload: payload)
    }

    /// Sets noise control from an explicit 16-bit mask.
    ///
    /// The field also accepts a few single-byte conveniences (`0x01` off, `0x02` NC at High,
    /// `0x04` transparency), which is why the older single-byte form appeared to work while
    /// mapping to the wrong modes. The explicit form is unambiguous and is the only one that
    /// can reach Adaptive or a specific level, so it is the only one sent.
    static func encodeSetNoiseMask(_ mask: UInt16) -> [UInt8] {
        makeFrame(0x00, 0x00, cmd: Setter.anc.rawValue,
                  messageType: MessageType.set.rawValue, sequence: nextSequence(),
                  payload: [0x01, 0x01, UInt8(mask & 0xff), UInt8(mask >> 8)])
    }

    static func encodeSetEQPreset(_ preset: EQPreset) -> [UInt8] {
        makeFrame(0x00, 0x00, cmd: Setter.eqPreset.rawValue,
                  messageType: MessageType.set.rawValue, sequence: nextSequence(),
                  payload: [preset.value])
    }

    /// BassWave: `[min][max][level]`, signed. The bounds are this unit's own `−5…+5` written
    /// out, not read from the getter: nothing reads the getter's bounds yet, and the self-check
    /// pins this payload against the captured `basswave-reply-2`, so a firmware that moved the
    /// bounds would fail a test rather than have the app keep writing the old ones.
    static func encodeSetBassWave(_ level: Int) -> [UInt8] {
        let clamped = Int8(clamping: max(-5, min(5, level)))
        return makeFrame(0x00, 0x00, cmd: Setter.bassWave.rawValue,
                         messageType: MessageType.set.rawValue, sequence: nextSequence(),
                         payload: [0xfb, 0x05, UInt8(bitPattern: clamped)])
    }

    /// Rings the given buds. Fire-and-forget: the tone stops itself and there is no opcode to
    /// stop it early, so the UI must not offer one.
    static func encodeFind(_ slots: [BatterySlot]) -> [UInt8] {
        // The count is one byte: more than 255 buds cannot be named. The UI offers two. Truncate
        // rather than trap, so a bad caller loses the command instead of the process.
        let ids = Array(slots.map(\.rawValue).prefix(255))
        return makeFrame(0x00, 0x00, cmd: Setter.find.rawValue,
                         messageType: MessageType.set.rawValue, sequence: nextSequence(),
                         payload: [UInt8(ids.count)] + ids)
    }

    /// One record of the getter's reply behind a count, per the "setter takes its getter's
    /// reply minus the status byte" rule that predicts every setter in this file.
    static func encodeSetTouch(_ rules: [TouchRule]) -> [UInt8] {
        // One count byte, so 255 records is the ceiling; the UI writes two, one per earbud.
        let rules = Array(rules.prefix(255))
        var payload: [UInt8] = [UInt8(rules.count)]
        for rule in rules { payload += [rule.side, rule.type, rule.gesture, rule.action] }
        return makeFrame(0x00, 0x00, cmd: Setter.touch.rawValue,
                         messageType: MessageType.set.rawValue, sequence: nextSequence(),
                         payload: payload)
    }

    /// Session opener. The buds answer it, and OPOv1 wants it before commands.
    static func encodeHello() -> [UInt8] {
        makeFrame(0x00, 0x00, cmd: 0x00, messageType: MessageType.request.rawValue,
                  sequence: nextSequence(), payload: [])
    }

    /// Monotonic per-session sequence byte.
    ///
    /// Static because nothing else in the framing carries state, and locked because a static
    /// mutable counter is the one piece of shared state in this file — the encoders are not
    /// declared main-actor, so two of them on different queues would otherwise race on `&+=`.
    private static let sequenceCounter = OSAllocatedUnfairLock(initialState: UInt8(0))

    static func nextSequence() -> UInt8 {
        sequenceCounter.withLock { counter in
            counter &+= 1
            return counter
        }
    }

    // MARK: - Receiving

    /// Pulls every complete frame out of `buffer`, leaving any partial tail behind.
    /// RFCOMM delivers arbitrary chunks, so frames both split and coalesce.
    static func drainFrames(from buffer: inout [UInt8]) -> [Frame] {
        var frames: [Frame] = []

        while true {
            // Resynchronise: drop anything before the next sync byte.
            guard let start = buffer.firstIndex(of: sync) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }

            guard buffer.count >= 2 else { break }

            // A varint is at most five bytes and a continuation byte never terminates one, so
            // five of them in a row can never become a value however much more arrives. That is
            // a bad byte, not a short read, and `decodeVarint` returns nil for both. Waiting here
            // would be permanent: no frame could ever complete, so every frame after the bad one
            // would be dropped for the life of the channel while `rxBuffer` grew without bound.
            if buffer.count >= 6, buffer[1...5].allSatisfy({ $0 & 0x80 != 0 }) {
                buffer.removeFirst()
                continue
            }
            // Otherwise a truncated varint is not a bad frame, only a short read — wait for more.
            guard let (length, varintLength) = decodeVarint(buffer[1...]) else { break }

            // `length` counts the seven remaining header bytes plus the payload — the sync byte
            // and the varint are the other two — so anything smaller cannot be a frame, and the
            // payload-length field is 16-bit, so nothing larger can be one either. Both mean this
            // was not a frame boundary: step over the sync byte and look for the next one. The
            // upper bound matters as much as the lower: without it an overlong varint decodes to
            // a length no buffer will ever reach, which waits forever exactly like a poison byte.
            guard length >= 7, length <= 7 + 0xffff else {
                buffer.removeFirst()
                continue
            }

            let total = 1 + varintLength + length
            guard buffer.count >= total else { break }   // wait for the rest

            let raw = Array(buffer[0..<total])
            let body = 1 + varintLength
            let payloadLength = Int(raw[body + 5]) | Int(raw[body + 6]) << 8
            if body + 7 + payloadLength == total {
                frames.append(Frame(
                    cmd: raw[body + 2],
                    messageType: raw[body + 3],
                    sequence: raw[body + 4],
                    payload: Array(raw[(body + 7)...]),
                    raw: raw))
                buffer.removeFirst(total)
            } else {
                // The two length fields disagree: this was not a frame boundary.
                buffer.removeFirst()
            }
        }

        return frames
    }

    /// Decodes an unsolicited frame — a status notification or a settings push.
    static func interpret(_ frame: Frame) -> [Update] {
        if frame.isStatusNotification { return statusTopic(frame.payload) }
        if frame.messageType == MessageType.stateChange.rawValue {
            return settingsPush(frame)
        }
        return []
    }

    /// Decodes a reply the app asked for. Same bodies as the pushes, each behind a status
    /// byte, so one decoder serves both.
    static func decode(reply frame: Frame) -> [Update] {
        guard frame.messageType == MessageType.reply.rawValue else { return [] }
        switch frame.cmd {
        case Command.battery.rawValue:
            return battery(body(withoutStatus: frame))
        case Command.wear.rawValue:
            return wear(body(withoutStatus: frame))
        case Command.anc.rawValue:
            return anc(body(withoutStatus: frame))
        case Command.eqPreset.rawValue:
            guard let value = body(withoutStatus: frame).first,
                  let preset = EQPreset(value: value) else { return [] }
            return [.eqPreset(preset)]
        case Command.bassWave.rawValue:
            guard let level = bassWaveLevel(body(withoutStatus: frame)) else { return [] }
            return [.bassWave(level)]
        default:
            return []
        }
    }

    /// The firmware string is ASCII, comma-separated, and does not fit the counted shape:
    /// `1,2,138,2,2,138,3,1,01,3,2,105` — component, ?, build, repeated.
    static func firmware(from frame: Frame) -> String? {
        guard frame.cmd == Command.firmware.rawValue,
              frame.messageType == MessageType.reply.rawValue,
              frame.payload.count >= 2 else { return nil }
        return String(decoding: frame.payload.dropFirst(2), as: UTF8.self)
    }

    /// The touch-gesture table: `[status][count]` then `count` four-byte records.
    /// The request payload is ignored by the firmware, so this is always sent empty.
    static func touchRules(from frame: Frame) -> [TouchRule]? {
        guard frame.cmd == Command.touch.rawValue,
              frame.messageType == MessageType.reply.rawValue else { return nil }
        let body = body(withoutStatus: frame)
        guard let count = body.first else { return nil }
        var rules: [TouchRule] = []
        var index = 1
        for _ in 0..<Int(count) {
            guard index + 3 < body.count else { break }
            rules.append(TouchRule(side: body[index], type: body[index + 1],
                                   gesture: body[index + 2], action: body[index + 3]))
            index += 4
        }
        return rules
    }

    /// The BassWave level out of `[min][max][current]`, all signed.
    static func bassWaveLevel(_ body: [UInt8]) -> Int? {
        guard body.count >= 3 else { return nil }
        return Int(Int8(bitPattern: body[2]))
    }

    private static func body(withoutStatus frame: Frame) -> [UInt8] {
        Array(frame.payload.dropFirst())
    }

    /// Family 1: `cmd 0x04`, `type 0x02`. `payload[0]` selects the topic and the rest is the
    /// corresponding reply with its status byte removed.
    private static func statusTopic(_ payload: [UInt8]) -> [Update] {
        guard let topic = payload.first else { return [] }
        let body = Array(payload.dropFirst())
        guard !body.isEmpty else { return [] }
        switch topic {
        case 0x01: return battery(body)
        case 0x02: return wear(body)
        // The ANC push is lossy on this hardware: some captures carry the full 16-bit value,
        // others only its low byte, and the low byte of Transparency (0x0100) and Adaptive
        // (0x0800) is 0x00 either way. `anc` handles both and stays silent when the value is
        // ambiguous, so the poll is what actually keeps the panel honest.
        case 0x03: return anc(body)
        default: return []
        }
    }

    /// Family 2: `type 0x05`, with the command byte naming the subject on its own numbering.
    ///
    /// The payload is the subject's *reply* payload minus its status byte — the same body a
    /// family-1 notification would carry, without a topic in front of it. So `0x0504`'s
    /// payload is the bare preset byte, not `[status][preset]`, and the two families share
    /// one set of decoders.
    private static func settingsPush(_ frame: Frame) -> [Update] {
        switch frame.cmd {
        case 0x04:   // EQ preset — a bare preset byte
            guard let value = frame.payload.first, let preset = EQPreset(value: value)
            else { return [] }
            return [.eqPreset(preset)]
        case 0x08:   // BassWave — `[min][max][current]`
            guard let level = bassWaveLevel(frame.payload) else { return [] }
            return [.bassWave(level)]
        default:
            return []
        }
    }

    private static func battery(_ body: [UInt8]) -> [Update] {
        guard let count = body.first else { return [] }
        return pairs(body, count: count).compactMap { id, raw in
            guard let slot = BatterySlot(rawValue: id) else { return nil }
            // A slot reads 0 while it is asleep or shut rather than dropping out of the
            // frame, and a genuinely flat battery is the rarer reading — so 0 means
            // unknown, and the UI shows a dash rather than a false 0%.
            let percent = Int(raw & 0x7f)
            return .battery(slot, percent == 0 ? nil : percent)
        }
    }

    private static func wear(_ body: [UInt8]) -> [Update] {
        guard let count = body.first else { return [] }
        return pairs(body, count: count).compactMap { id, flags in
            guard let slot = BatterySlot(rawValue: id),
                  let placement = BudPlacement(rawValue: flags) else { return nil }
            return .placement(slot, placement)
        }
    }

    private static func anc(_ body: [UInt8]) -> [Update] {
        guard let count = body.first, count == 1, body.count >= 3 else { return [] }
        guard body[1] == noiseModeID else { return [] }
        // Two bytes when the whole value is present, one when the push was lossy.
        let mask = body.count >= 4
            ? UInt16(body[2]) | UInt16(body[3]) << 8
            : UInt16(body[2])
        guard let mode = NoiseMode(mask: mask) else { return [] }
        guard mode == .noiseCancellation, let level = ANCLevel(mask: mask) else {
            return [.noiseMode(mode)]
        }
        return [.noiseMode(mode), .ancLevel(level)]
    }

    /// Reads `count` two-byte `[id][value]` records starting after the count.
    private static func pairs(_ body: [UInt8], count: UInt8) -> [(UInt8, UInt8)] {
        var out: [(UInt8, UInt8)] = []
        var index = 1
        for _ in 0..<Int(count) {
            guard index + 1 < body.count else { break }
            out.append((body[index], body[index + 1]))
            index += 2
        }
        return out
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// One-line summary of a frame, for the trace and for `Tools/sniff.swift`.
    static func describe(_ frame: Frame) -> String {
        let kind = MessageType(rawValue: frame.messageType).map { "\($0)" } ?? "unknown"
        return "cmd=\(String(format: "%02x", frame.cmd)) "
            + "type=\(String(format: "%02x", frame.messageType)) \(kind) "
            + "seq=\(String(format: "%02x", frame.sequence)) "
            + "payload=[\(hex(frame.payload))]"
    }

    // MARK: - Self check

    /// The outcome of a `selfCheck()` run.
    public struct SelfCheckResult {
        public var checks = 0
        public var failures: [String] = []
        public var passed: Bool { failures.isEmpty }
    }

    /// True when the process was started as `--selfcheck`. `BudsBar.launch()` reads this
    /// before it creates anything, so a check run never constructs an app.
    public static let isSelfCheckRun = CommandLine.arguments.contains("--selfcheck")

    /// Re-derives a frame's length fields from its payload and compares them with the bytes
    /// that are actually there.
    ///
    /// This is the invariant that makes a frame a frame: `len` is a varint covering
    /// `7 + payload.count`, and the payload-length field has to agree with it. Re-encoding is
    /// the honest way to test it — it is a property of the bytes rather than a second opinion
    /// about them — and it catches the class of mistake this file used to contain, where a
    /// typed-out fixture carried a `len` describing different bytes than it held.
    static func lengthFieldsAgree(_ frame: Frame) -> Bool {
        let declared = encodeVarint(7 + frame.payload.count)
        let body = 1 + declared.count
        // A frame is `sync + varint + 7 header bytes + payload`, so an empty-payload frame is
        // exactly `body + 7` bytes — this is a floor, not a strict bound. Getting it wrong made
        // this function disagree with `drainFrames`, which accepts that frame: the validator
        // called malformed the very shape the app sends as its own session opener.
        guard frame.raw.count >= body + 7 else { return false }
        guard Array(frame.raw[1..<body]) == declared else { return false }
        let payloadLength = Int(frame.raw[body + 5]) | Int(frame.raw[body + 6]) << 8
        return body + 7 + payloadLength == frame.raw.count
    }

    /// Runs every check against the captured corpus and reports, rather than trapping.
    ///
    /// `assert` would have been shorter, and was what this used, but it is compiled out of
    /// release builds — which is what ships. A protocol regression would then go out silently,
    /// as the app quietly commanding the wrong mode, which is exactly the bug these checks
    /// exist to prevent. Reporting a result instead means the same code runs as a real check
    /// from `build.sh`, from `swift test`, and as a launch-time guard in debug.
    @discardableResult
    public static func selfCheck() -> SelfCheckResult {
        var result = SelfCheckResult()
        func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
            result.checks += 1
            if !condition() { result.failures.append(message()) }
        }

        // MARK: The corpus itself

        // Every fixture has to *be* a frame before anything is decoded from it, and this is
        // the check whose absence caused the crash: the fixtures were typed out by hand, one
        // carried a `len` varint that disagreed with its own payload-length field,
        // `drainFrames` correctly rejected it, and the check that followed indexed `[0]` of
        // an empty array. A bad fixture now fails here, by name, and the decoders below run
        // against a placeholder — so the report names the cause instead of the process dying.
        var captured: [String: Frame] = [:]
        let placeholder = Frame(cmd: 0, messageType: 0, sequence: 0, payload: [], raw: [])
        for capture in FixtureCorpus.frames {
            var buffer = capture.bytes
            let parsed = drainFrames(from: &buffer)
            check(parsed.count == 1 && buffer.isEmpty,
                  "\(capture.name): capture is not exactly one frame "
                  + "(\(parsed.count) parsed, \(buffer.count) bytes left over)")
            guard let frame = parsed.first else {
                captured[capture.name] = placeholder
                continue
            }
            check(lengthFieldsAgree(frame),
                  "\(capture.name): length fields disagree with the bytes they describe")
            captured[capture.name] = frame
        }

        func capture(_ name: String) -> Frame {
            guard let frame = captured[name] else {
                check(false, "\(name): no such capture in the corpus")
                return placeholder
            }
            return frame
        }

        /// A variant of a captured frame with a different payload.
        ///
        /// States the hardware did not happen to be in while the capture was taken — a case
        /// that has gone to sleep, a charging bit, a push cut short — are derived here rather
        /// than typed out. `makeFrame` recomputes both length fields, so a derived fixture
        /// cannot disagree with itself. That is the whole lesson of the crash: bytes are fine,
        /// hand-written lengths are not.
        func derived(_ name: String, from base: Frame, payload: [UInt8],
                     cmd: UInt8? = nil, messageType: UInt8? = nil) -> Frame {
            var buffer = makeFrame(0x00, 0x00, cmd: cmd ?? base.cmd,
                                   messageType: messageType ?? base.messageType,
                                   sequence: base.sequence, payload: payload)
            let parsed = drainFrames(from: &buffer)
            guard parsed.count == 1, buffer.isEmpty, let frame = parsed.first else {
                check(false, "\(name): derived frame is not well formed")
                return placeholder
            }
            return frame
        }

        /// A family-1 notification derived from a capture. The command byte and message type
        /// are what make it a notification at all, so they are set rather than inherited — the
        /// first version of this derived them from a *reply* and every check downstream failed
        /// for a reason that had nothing to do with the decoder under test.
        func notification(_ name: String, from base: Frame, payload: [UInt8]) -> Frame {
            derived(name, from: base, payload: payload,
                    cmd: statusNotificationCommand, messageType: MessageType.notification.rawValue)
        }

        // MARK: Framing

        // A 299-byte payload produces a 306-byte length, which needs two varint bytes. A
        // single-byte reading predicts 180 and mis-frames the stream from there on.
        check(encodeVarint(306) == [0xb2, 0x02], "306 is a two-byte varint")
        check(encodeVarint(7) == [0x07], "small lengths stay one byte")
        check(decodeVarint([0xb2, 0x02])?.value == 306, "varint round-trips")
        check(decodeVarint([0x80]) == nil, "a dangling continuation byte is not a value")

        let big = makeFrame(0, 0, cmd: 0x1f, messageType: 0x81, sequence: 1,
                            payload: Array(repeating: 0, count: 299))
        check(big[1] == 0xb2 && big[2] == 0x02, "big frame length is a varint")
        var bigBuffer = big
        let bigFrames = drainFrames(from: &bigBuffer)
        check(bigFrames.count == 1 && bigFrames[0].payload.count == 299,
               "a 299-byte payload parses whole")

        // An empty payload is legal, and it is not a corner case: it is the shape of the app's
        // own session opener. The validator used to require `raw.count > body + 7`, which is
        // exactly the size of that frame, so it called the app's own hello malformed while the
        // parser accepted it — one invariant written twice, and disagreeing.
        var emptyBuffer = encodeHello()
        let emptyFrames = drainFrames(from: &emptyBuffer)
        check(emptyFrames.count == 1, "an empty-payload frame parses")
        check(emptyFrames.first.map { lengthFieldsAgree($0) } == true,
              "an empty-payload frame satisfies the length invariant")

        // A byte pattern that can never be a varint has to be stepped over, not waited on. Waiting
        // is right for a short read; a poison byte needs the opposite, and confusing the two makes
        // the parser deaf for the life of the channel. Each input is one bad frame followed by a
        // good one, so this checks not just that nothing hangs but that the parse recovers.
        let poisons: [(String, [UInt8])] = [
            ("five continuation bytes", [sync, 0x80, 0x80, 0x80, 0x80, 0x80]),
            ("an overlong varint length", [sync, 0x80, 0x80, 0x80, 0x80, 0x7f]),
        ]
        for (label, poison) in poisons {
            var buffer = poison + big
            let recovered = drainFrames(from: &buffer)
            check(recovered.count == 1 && recovered[0].payload.count == 299 && buffer.isEmpty,
                  "\(label): the parser resynchronises instead of stalling")
        }

        // MARK: Handshake

        let hello = capture("hello-reply")
        check(hello.cmd == 0x00 && hello.messageType == MessageType.reply.rawValue,
              "the hello reply is a single reply frame")
        check(Array(hello.payload.dropFirst())
                == [0xff, 0x77, 0x5a, 0xea, 0x67, 0x0e, 0x20, 0x07],
              "the hello reply is the static 8-byte value, not a session token")
        check(interpret(hello).isEmpty, "the hello reply is not a status update")

        // MARK: Battery

        let battery = capture("battery-reply")
        check(decode(reply: battery) == [.battery(.left, 20), .battery(.right, 20)],
              "battery reply, case absent: \(decode(reply: battery))")

        // The same report arriving as a family-1 notification, topic 0x01. Derived, because
        // the notification body is the reply body with a topic in front of it — that identity
        // is the reason one decoder serves both.
        let batteryPush = notification("battery-push", from: battery,
                                       payload: [0x01] + Array(battery.payload.dropFirst()))
        check(interpret(batteryPush) == [.battery(.left, 20), .battery(.right, 20)],
              "battery push: \(interpret(batteryPush))")

        // A sleeping case reads as unknown, not 0%.
        let sleepingCase = notification("battery-push-sleeping-case", from: battery,
                                        payload: [0x01, 0x03, 0x01, 0x14, 0x02, 0x14, 0x03, 0x00])
        check(interpret(sleepingCase) == [.battery(.left, 20), .battery(.right, 20),
                                          .battery(.enclosure, nil)],
              "a sleeping case is unknown, and says so rather than staying silent")

        // A slot that is absent from the report must not be invented: the two-bud capture has
        // no case entry at all, and the decoder emits nothing for it.
        check(interpret(batteryPush).contains(.battery(.enclosure, 20)) == false,
              "an absent slot is not the same as an unknown one")

        // The charging bit lives in the top bit and must not be read as part of the level.
        let charging = derived("battery-reply-charging", from: battery,
                               payload: [0x00, 0x02, 0x01, 0x94, 0x02, 0x14])
        check(decode(reply: charging) == [.battery(.left, 20), .battery(.right, 20)],
              "0x80 is a charging flag, not 148%: \(decode(reply: charging))")

        // MARK: Wear

        let wear = capture("wear-reply")
        check(decode(reply: wear) == [.placement(.left, .inEar),
                                      .placement(.right, .inEar),
                                      .placement(.enclosure, .inCase)],
              "wear flags: \(decode(reply: wear))")

        // Being held is neither in the ear nor put away, and must not be rounded to either.
        let held = derived("wear-held", from: wear,
                           payload: [0x00, 0x03, 0x01, 0x05, 0x02, 0x07, 0x03, 0x04])
        check(decode(reply: held) == [.placement(.left, .outOfCase),
                                      .placement(.right, .inEar),
                                      .placement(.enclosure, .inCase)],
              "held is its own state: \(decode(reply: held))")

        // MARK: Noise control

        // These four are the table the app got wrong: it sent 0x02 for Transparency and 0x08
        // for ANC, and the firmware stored Noise cancellation and Off.
        check(decode(reply: capture("anc-reply-off")) == [.noiseMode(.off)], "0x0008 is Off")
        check(decode(reply: capture("anc-reply-nc-high"))
                == [.noiseMode(.noiseCancellation), .ancLevel(.high)],
              "0x0010 is Noise cancellation at High, not Transparency")
        check(decode(reply: capture("anc-reply-transparency")) == [.noiseMode(.transparency)],
              "0x0100 is Transparency")
        check(decode(reply: capture("anc-reply-adaptive")) == [.noiseMode(.adaptive)],
              "0x0800 is Adaptive")

        for (name, level) in [("anc-reply-nc-moderate", ANCLevel.moderate),
                              ("anc-reply-nc-low", ANCLevel.low),
                              ("anc-reply-nc-auto", ANCLevel.auto)] {
            check(decode(reply: capture(name))
                    == [.noiseMode(.noiseCancellation), .ancLevel(level)],
                  "\(name) is Noise cancellation at \(level.label)")
        }

        // A mask from newer firmware is ignored rather than rounded to a nearby mode.
        let unknownMask = derived("anc-reply-unknown-mask", from: capture("anc-reply-off"),
                                  payload: [0x00, 0x01, 0x01, 0x00, 0x40])
        check(decode(reply: unknownMask).isEmpty, "an unmodelled mask yields no update")

        // The push carries only the low byte, so 0x00 cannot be told apart between
        // Transparency and Adaptive and must produce nothing at all.
        let lossyOff = notification("anc-push-low-byte-off", from: capture("anc-reply-off"),
                                    payload: [0x03, 0x01, 0x01, 0x08])
        check(interpret(lossyOff) == [.noiseMode(.off)], "the low byte still identifies Off")
        let lossyAmbiguous = notification("anc-push-low-byte-ambiguous", from: capture("anc-reply-off"),
                                          payload: [0x03, 0x01, 0x01, 0x00])
        check(interpret(lossyAmbiguous).isEmpty,
              "a truncated push is not evidence of Transparency")

        // Every mode and level the UI can select reads back as the firmware would describe it.
        // The base is a real readback, so the header and both length fields stay well formed —
        // but the value is generated, so this proves only that the mask table and its inverse
        // agree. The captured `anc-reply-*` checks above are what pin the masks themselves.
        for mode in NoiseMode.allCases {
            let reply = derived("anc-reply-\(mode.rawValue)", from: capture("anc-reply-off"),
                                payload: [0x00, 0x01, 0x01,
                                          UInt8(mode.mask & 0xff), UInt8(mode.mask >> 8)])
            check(decode(reply: reply).contains(.noiseMode(mode)),
                  "\(mode.label) round-trips: \(decode(reply: reply))")
        }
        for level in ANCLevel.allCases {
            let reply = derived("anc-reply-\(level.rawValue)", from: capture("anc-reply-off"),
                                payload: [0x00, 0x01, 0x01,
                                          UInt8(level.mask & 0xff), UInt8(level.mask >> 8)])
            check(decode(reply: reply).contains(.ancLevel(level)),
                  "level \(level.label) round-trips: \(decode(reply: reply))")
        }

        // MARK: EQ, BassWave, firmware

        let eqBalanced = capture("eq-reply-balanced")
        let eqBass = capture("eq-reply-bass")
        check(decode(reply: eqBalanced) == [.eqPreset(.balanced)],
              "the Balanced readback: \(decode(reply: eqBalanced))")
        check(decode(reply: eqBass) == [.eqPreset(.bass)],
              "the Bass readback: \(decode(reply: eqBass))")

        // The buds push EQ changes as family 2: type 0x05, the subject in the command byte on
        // its own numbering, and the payload equal to the getter's reply payload minus its
        // status byte. Asserting that identity is what lets one set of decoders serve both.
        let eqPush = capture("eq-push-bass")
        check(interpret(eqPush) == [.eqPreset(.bass)], "the EQ push uses its own numbering")
        let eqPushBalanced = capture("eq-push-balanced")
        check(interpret(eqPushBalanced) == [.eqPreset(.balanced)], "the Balanced EQ push")
        check(eqPush.payload == Array(eqBass.payload.dropFirst()),
              "the push body is the reply body minus the status byte: \(hex(eqPush.payload))")

        let bass0 = capture("basswave-reply-0")
        let bass2 = capture("basswave-reply-2")
        check(decode(reply: bass0) == [.bassWave(0)], "a signed BassWave level")
        check(decode(reply: bass2) == [.bassWave(2)], "and another")

        // Not observed on this unit — the phone's own writes are what raise it — so it is
        // derived from the family-2 shape with subject 0x08, whose payload is the 0x041B
        // setter's body byte for byte.
        let bassPush = derived("basswave-push", from: eqPush,
                               payload: [0xfb, 0x05, 0x02], cmd: 0x08)
        check(interpret(bassPush) == [.bassWave(2)], "the BassWave push: \(interpret(bassPush))")

        check(firmware(from: capture("firmware-reply")) == "1,2,138,2,2,138,3,1,01,3,2,105",
              "firmware is an ASCII string, not a binary structure")

        let customEQ = capture("custom-eq-reply")
        check(customEQ.payload.dropFirst().first == 0x00,
              "this unit has no saved custom EQ profile: \(hex(customEQ.payload))")

        // MARK: Touch

        let touch = capture("touch-reply")
        let rules = touchRules(from: touch)
        check(rules?.count == 18, "18 gesture records, got \(rules?.count ?? -1)")
        check(rules?.first == TouchRule(side: 0x01, type: 0x01, gesture: 0x01, action: 0x00),
              "first record")
        check(rules?.last == TouchRule(side: 0x02, type: 0x06, gesture: 0x06, action: 0x1c),
              "the record walk closes exactly on the end of the payload")

        // MARK: The setter namespace

        // A set is acknowledged by a `0x84` frame addressed to the *setter* id, so the
        // captured acks are evidence from the hardware for the ids this file sends — and for
        // the claim that the setter ids are a different namespace from the getters'.
        let setOff = encodeSetNoiseMask(NoiseMode.off.mask)
        check(setOff.count == 13, "an ANC set is 13 bytes: \(hex(setOff))")
        check(Array(setOff[9...]) == [0x01, 0x01, 0x08, 0x00],
              "the explicit 16-bit mask, not the single byte that cannot express Adaptive")
        check(setOff[4] == Setter.anc.rawValue && setOff[4] == capture("setack-anc").cmd,
              "the ANC setter id is the one the hardware acknowledges")
        check(setOff[5] == MessageType.set.rawValue, "and it is a set, not a request")
        var setBuffer = setOff
        let setFrames = drainFrames(from: &setBuffer)
        check(setFrames.count == 1 && setBuffer.isEmpty, "the set frame parses as one frame")
        check(interpret(setFrames.first ?? placeholder).isEmpty,
              "a set frame is not a status update")

        let setEQ = encodeSetEQPreset(.bass)
        check(Array(setEQ[9...]) == Array(eqBass.payload.dropFirst()),
              "the EQ setter takes its getter's reply payload minus the status byte")
        check(setEQ[4] == capture("setack-eq").cmd, "the EQ setter id is the acknowledged one")

        let setBass = encodeSetBassWave(2)
        check(Array(setBass[9...]) == Array(bass2.payload.dropFirst()),
              "the BassWave setter echoes the getter's bounds: \(hex(setBass))")
        check(setBass[4] == Setter.bassWave.rawValue
                && setBass[4] == capture("setack-basswave").cmd,
              "BassWave's setter is 0x1B, not the getter's 0x24")
        check(encodeSetBassWave(99).last == 0x05, "the level is clamped to the hardware range")
        check(encodeSetBassWave(-99).last == 0xfb, "clamped at the bottom too")

        // A touch write is one record behind its count, and the record it writes back has to
        // be the one that was read. That is the guarantee the gesture editor depends on:
        // every write is a verbatim re-send of a record the buds already store.
        if let rule = rules?.first(where: { $0.type == TouchRule.media
                                            && $0.side == TouchRule.left }) {
            let setTouch = encodeSetTouch([rule])
            check(Array(setTouch[9...]) == [0x01, rule.side, rule.type, rule.gesture, rule.action],
                  "one touch record behind its count: \(hex(setTouch))")
            check(setTouch[4] == Setter.touch.rawValue, "the touch setter id")
        } else {
            check(false, "the capture has no media-context record on the left to write back")
        }

        // Find is a count-prefixed id list. These three payloads are the ones measured
        // independently against the hardware, so the encoder is checked against bytes it did
        // not produce.
        check(Array(encodeFind([.left])[9...]) == [0x01, 0x01], "find left only")
        check(Array(encodeFind([.right])[9...]) == [0x01, 0x02], "find right only")
        check(Array(encodeFind([.left, .right])[9...]) == [0x02, 0x01, 0x02], "find both")

        // MARK: Frames that must not move anything

        // The only family-1 notification this unit sends unprompted is the device table — a
        // topic this app does not model. It must be recognised as a notification and then
        // ignored, not mistaken for a setting.
        let devices = capture("notify-devices")
        check(devices.isStatusNotification, "a 0x0204 frame is a status notification")
        check(interpret(devices).isEmpty, "an unmodelled topic yields no update")

        for name in ["setack-anc", "setack-eq", "setack-basswave"] {
            check(interpret(capture(name)).isEmpty, "\(name) is never a status update")
        }

        // MARK: Resilience

        // Two frames coalesced in one read.
        var coalesced = battery.raw + eqBass.raw
        check(drainFrames(from: &coalesced).count == 2, "coalesced frames")
        check(coalesced.isEmpty, "and nothing is left over")

        // One frame split across two reads: the tail must be held, not misparsed.
        var split = Array(battery.raw[0..<6])
        check(drainFrames(from: &split).isEmpty, "a partial frame is withheld")
        split.append(contentsOf: battery.raw[6...])
        check(drainFrames(from: &split).count == 1, "the frame completes across reads")

        // Leading garbage before the sync byte must be skipped, not fatal.
        var garbage: [UInt8] = [0xff, 0xff] + battery.raw
        check(drainFrames(from: &garbage).count == 1, "resynchronised past garbage")

        // A varint cut in half by the chunk boundary must wait, not resync.
        var cutVarint: [UInt8] = [0xaa, 0xb2]
        check(drainFrames(from: &cutVarint).isEmpty, "a half-read varint waits")
        check(cutVarint.count == 2, "and keeps its bytes")

        // A frame whose length fields disagree is not a frame: it is dropped and the scan
        // resumes, rather than being handed to a decoder as though it were one. This is the
        // behaviour the crash depended on being right.
        var malformed = battery.raw
        malformed[1] = 0x0e                     // claim one byte more than is present
        check(drainFrames(from: &malformed).isEmpty, "a lying length field is rejected")

        return result
    }

    /// Prints the check results and exits non-zero if any failed. Called by `build.sh` and by
    /// the test suite, so a protocol regression fails the build instead of shipping.
    public static func runSelfCheckAndExit() -> Never {
        let result = selfCheck()
        for failure in result.failures {
            FileHandle.standardError.write(Data("selfCheck FAILED: \(failure)\n".utf8))
        }
        let summary = result.passed
            ? "selfCheck passed: \(result.checks) checks\n"
            : "selfCheck FAILED: \(result.failures.count) of \(result.checks) checks\n"
        FileHandle.standardError.write(Data(summary.utf8))
        exit(result.passed ? 0 : 1)
    }
}
