import XCTest
@testable import BudsBarKit

/// The protocol checks, as tests rather than as a hook that runs at launch.
///
/// `BudsProtocol.selfCheck()` is the same code `build.sh` runs against the shipped binary;
/// this suite is what makes it reachable by `swift test`, so a protocol regression fails a
/// normal test run. Everything asserted here runs against `FixtureCorpus` — frames taken off
/// the wire — and nothing against a reconstruction, which is the mistake that produced the
/// crash this suite exists to prevent recurring.
final class ProtocolTests: XCTestCase {

    private typealias Gesture = BudsProtocol.MediaGesture

    // MARK: The checks themselves

    func testSelfCheckReportsNoFailures() {
        let result = BudsProtocol.selfCheck()
        XCTAssertTrue(result.checks > 40, "only \(result.checks) checks ran — did the corpus load?")
        XCTAssertEqual(result.failures, [], "\n" + result.failures.joined(separator: "\n"))
        XCTAssertTrue(result.passed)
    }

    func testSelfCheckIsRepeatable() {
        // The check builds derived frames with `makeFrame`, which draws a sequence number
        // from static state. If sequence leaked into an expectation, a second run would
        // fail; it must not, because a check that only passes first time is not a check.
        _ = BudsProtocol.selfCheck()
        XCTAssertEqual(BudsProtocol.selfCheck().failures, [])
    }

    /// The contract the 1.0.0 crash broke, and the whole reason `selfCheck` reports a result
    /// rather than asserting: a corpus that does not add up has to come back as a list of
    /// failures. It used to come back as an index-out-of-range, in the check that followed the
    /// count assertion which had just proved the array was too short — so the run died with a
    /// trap and never printed the failure it had already collected.
    ///
    /// The capture is truncated mid-frame: the shortest thing that leaves every downstream read
    /// of it with nothing to read. That reaching the assertions at all is the test — if a
    /// subscript in `selfCheck` ever stops being total, this does not fail, it crashes.
    func testSelfCheckReportsRatherThanTrapsOnADegradedCorpus() {
        let truncated = FixtureCorpus.frames.map { capture in
            capture.name == "battery-reply"
                ? FixtureCorpus.Capture(name: capture.name,
                                        note: "truncated mid-frame, for the checks about checks",
                                        hex: "aa 0d 00 00 06 81 03 06 00 00")
                : capture
        }

        let result = BudsProtocol.selfCheck(corpus: truncated)

        XCTAssertFalse(result.passed, "a corpus that is not a corpus must not pass")
        XCTAssertTrue(result.failures.contains { $0.contains("battery-reply") },
                      "the report must name the fixture it could not read:\n"
                      + result.failures.joined(separator: "\n"))
    }

    // MARK: The corpus is a corpus

    /// The property, rather than a second opinion about the bytes: for every capture, both
    /// length fields have to describe the bytes that are actually present.
    func testEveryCaptureIsOneFrameWithConsistentLengths() throws {
        XCTAssertFalse(FixtureCorpus.frames.isEmpty)
        for capture in FixtureCorpus.frames {
            var buffer = capture.bytes
            let frames = BudsProtocol.drainFrames(from: &buffer)
            XCTAssertEqual(frames.count, 1, "\(capture.name): not exactly one frame")
            XCTAssertTrue(buffer.isEmpty, "\(capture.name): \(buffer.count) bytes left over")
            let frame = try XCTUnwrap(frames.first)
            XCTAssertTrue(BudsProtocol.lengthFieldsAgree(frame),
                          "\(capture.name): length fields disagree with the bytes")
        }
    }

    /// The frozen Swift literal and the hex file of record must not drift apart. This is what
    /// makes `Tools/freeze-fixtures.sh` the only way bytes get into the corpus.
    func testFrozenCorpusMatchesTheHexFileOfRecord() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // Tests/BudsBarKitTests
            .deletingLastPathComponent()            // Tests
            .appendingPathComponent("Fixtures/buds4-frames.hex")
        let text = try String(contentsOf: url, encoding: .utf8)

        var fromFile: [(String, String)] = []
        for line in text.split(separator: "\n") {
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let hex = line[line.index(after: separator)...]
                .split(separator: " ").joined(separator: " ")
            fromFile.append((name, hex))
        }

        XCTAssertEqual(fromFile.map(\.0), FixtureCorpus.frames.map(\.name),
                       "the corpus names differ from Tests/Fixtures/buds4-frames.hex — "
                       + "run Tools/freeze-fixtures.sh")
        XCTAssertEqual(fromFile.map(\.1), FixtureCorpus.frames.map(\.hex),
                       "the corpus bytes differ from Tests/Fixtures/buds4-frames.hex — "
                       + "run Tools/freeze-fixtures.sh")
    }

    // MARK: The crash, as a test

    /// Feeding a decoder bytes that are not a frame must produce nothing, not a trap.
    ///
    /// The original crash was a fixture whose `len` varint disagreed with its payload-length
    /// field; `drainFrames` rejected it, and the caller indexed `[0]` of the empty result.
    /// Every capture is therefore replayed truncated, extended, and with a corrupted length,
    /// and the only assertion that matters is that this test finishes.
    func testMalformedInputIsRejectedRatherThanTrapping() throws {
        for capture in FixtureCorpus.frames {
            let bytes = capture.bytes
            let cut = Array(bytes[0..<max(1, bytes.count - 3)])
            let over = bytes + [0x00, 0x00, 0x00]
            var lying = bytes
            lying[1] = 0x7f
            let doubled = bytes + bytes

            for (label, input) in [("truncated", cut), ("overlong", over),
                                   ("lying length", lying), ("duplicated", doubled)] {
                var buffer = input
                let frames = BudsProtocol.drainFrames(from: &buffer)
                for frame in frames {
                    // Anything that does come back must be a well-formed frame, so a decoder
                    // can never be handed a length that contradicts the bytes.
                    XCTAssertTrue(BudsProtocol.lengthFieldsAgree(frame),
                                  "\(capture.name) (\(label)): parser emitted a malformed frame")
                    // An empty payload is legal — it is the shape of the app's own hello — so the
                    // assertion is that the frame re-parses to itself, not that it carries a
                    // payload. Asserting non-empty encoded an accident of the corpus.
                    var again = frame.raw
                    let reparsed = BudsProtocol.drainFrames(from: &again)
                    XCTAssertEqual(reparsed.first?.raw ?? [], frame.raw,
                                   "\(capture.name) (\(label)): a parsed frame does not re-parse to itself")
                }
            }
        }
    }

    // MARK: Properties the UI depends on

    /// The multi-connect table, decoded from the one capture of it the corpus holds.
    ///
    /// The layout is the vendor SDK's own parser — a count, then records of six address bytes, a
    /// length byte, a state byte, a flag byte, a length-prefixed name — and the point of this
    /// test is the claim that makes it more than a fit to one sample: under that layout the
    /// second record lands on byte 35 of the 55-byte body and the pair consumes the body
    /// *exactly*, with nothing left over and nothing missing. A stride that was one byte out
    /// would not do that.
    /// The codec getter, end to end, against the capture: the reply's second byte is an id in
    /// the vendor's own codec list, and the app names it the way that list does.
    func testTheCodecGetterNamesTheIdTheVendorNames() throws {
        let capture = try XCTUnwrap(
            FixtureCorpus.frames.first { $0.name == "codec-reply" },
            "the codec capture is missing from the corpus")
        var bytes = capture.bytes
        let frame = try XCTUnwrap(BudsProtocol.drainFrames(from: &bytes).first,
                                  "the codec capture did not parse")
        XCTAssertTrue(bytes.isEmpty, "the capture is more than the one frame")
        XCTAssertEqual(frame.cmd, BudsProtocol.Command.codec.rawValue)

        XCTAssertEqual(BudsProtocol.decode(reply: frame), [.codec(.aac)],
                       "the capture's id 02 should read as AAC")
        XCTAssertEqual(BudsProtocol.Codec(rawValue: 0x02)?.label, "AAC")
        XCTAssertEqual(BudsProtocol.Codec(rawValue: 0x01)?.label, "SBC")
        XCTAssertEqual(BudsProtocol.Codec(rawValue: 0x03)?.label, "LDAC")
        // The two LHDC entries the vendor's list carries are labelled alike there, so they are
        // labelled alike here rather than being told apart by a guess at which revision.
        XCTAssertEqual(BudsProtocol.Codec(rawValue: 0x07)?.label, "LHDC")
        XCTAssertEqual(BudsProtocol.Codec(rawValue: 0x08)?.label, "LHDC")
        XCTAssertNil(BudsProtocol.Codec(rawValue: 0x00), "0 is not a codec in the vendor's list")
        XCTAssertNil(BudsProtocol.Codec(rawValue: 0x09))
    }

    /// The status byte: a reply only decodes past a `00`. This is not hypothetical — four of the
    /// getters the vendor's SDK names answer a bare `01` on this hardware, so a decoder that
    /// skimmed the byte off would read `[01 03]` as a counted table of three records.
    func testADeclinedReplyDecodesToNothing() throws {
        let capture = try XCTUnwrap(
            FixtureCorpus.frames.first { $0.name == "anc-reply-off" },
            "the ANC capture is missing from the corpus")
        var bytes = capture.bytes
        let frame = try XCTUnwrap(BudsProtocol.drainFrames(from: &bytes).first)

        XCTAssertEqual(BudsProtocol.decode(reply: frame), [.noiseMode(.off)],
                       "the OK status byte is 00 and the answer follows it")
        let declined = BudsProtocol.Frame(cmd: frame.cmd, messageType: frame.messageType,
                                          sequence: frame.sequence, payload: [0x01, 0x03],
                                          raw: frame.raw)
        XCTAssertTrue(BudsProtocol.decode(reply: declined).isEmpty,
                      "a declined reply must not be read as a three-record body")
    }

    func testTheDeviceTableDecodesToWhatTheCaptureRecords() throws {
        let capture = try XCTUnwrap(
            FixtureCorpus.frames.first { $0.name == "notify-devices" },
            "the device-table capture is missing from the corpus")
        var bytes = capture.bytes
        let frame = try XCTUnwrap(BudsProtocol.drainFrames(from: &bytes).first,
                                  "the device-table capture did not parse")
        XCTAssertTrue(bytes.isEmpty, "the capture is more than the one frame")
        let body = Array(frame.payload.dropFirst())

        let table = try XCTUnwrap(BudsProtocol.linkedDevices(body),
                                  "the captured table did not decode")
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table.first?.name, "Shashank’s MacBook Pro")
        XCTAssertEqual(table.first?.address, "26:68:69:83:be:b0")
        XCTAssertEqual(table.first?.state, .connected)
        XCTAssertEqual(table.first?.isCurrentDevice, true)
        XCTAssertEqual(table.first?.isMainAudioDevice, false)
        XCTAssertEqual(table.first?.isAudioActive, false)
        XCTAssertNil(table.first?.deviceType, "this capture leaves the device-type bits unset")
        XCTAssertEqual(table.dropFirst().first?.name, "shsxnk S23")
        XCTAssertEqual(table.dropFirst().first?.state, .notConnected)
        XCTAssertEqual(table.dropFirst().first?.isCurrentDevice, false)

        // The stride, stated as an assertion rather than as a comment: walking the records by
        // `7 + length` from the count byte has to land the second record where the capture
        // shows it and end on the body's last byte, with nothing left over and nothing missing.
        // This is the part a fit to one sample could not fake, and it is why the second record's
        // six address bytes start at 35 rather than at the first `00` inside its name.
        var offset = 1
        var offsets: [Int] = []
        while offsets.count < table.count {
            offsets.append(offset)
            offset += 7 + Int(body[offset + 6])
        }
        XCTAssertEqual(offsets, [1, 35], "records begin where the previous record's stride says")
        XCTAssertEqual(offset, body.count, "and the last one ends on the body's last byte")

        // A length byte that disagrees with the name it precedes is not a table this app can
        // read, and the honest answer is no update rather than a list fitted around the damage.
        var mismatched = body
        mismatched[7] = 0x1c
        XCTAssertNil(BudsProtocol.linkedDevices(mismatched))
        XCTAssertNil(BudsProtocol.linkedDevices(Array(body.dropLast(4))), "a truncated record")
        XCTAssertNil(BudsProtocol.linkedDevices([0x03] + body), "a count past the body")
        XCTAssertEqual(BudsProtocol.linkedDevices([0x00]), [], "a zero count is an empty table")

        // The same table read back on request. The reply is the push's body behind a status
        // byte, so the same decoder serves it, and this is the capture that proves the getter
        // works: the request is `0x12` with an empty payload, exactly as the vendor SDK sends it.
        let replyCapture = try XCTUnwrap(
            FixtureCorpus.frames.first { $0.name == "multiconnect-reply" },
            "the getter's reply is missing from the corpus")
        var replyBytes = replyCapture.bytes
        let replyFrame = try XCTUnwrap(BudsProtocol.drainFrames(from: &replyBytes).first)
        XCTAssertTrue(replyBytes.isEmpty, "the reply capture is more than the one frame")

        guard case .linkedDevices(let readBack)? = BudsProtocol.decode(reply: replyFrame).first else {
            return XCTFail("the getter's reply did not decode to a device table")
        }
        XCTAssertEqual(readBack.map(\.name), table.map(\.name))
        XCTAssertEqual(readBack.dropFirst().first?.state, .connected,
                       "the phone had connected by the time of the reply")
        XCTAssertEqual(replyFrame.payload.first, 0x00, "the reply's status byte leads the body")
        // The two captures differ in exactly two bytes — the reply's status byte and the phone's
        // state — which is what makes them two frames rather than two readings of one moment.
        var aligned = body
        aligned[42] = 0x02
        XCTAssertEqual(aligned, Array(replyFrame.payload.dropFirst()))
    }

    /// Every mask the UI can offer has to decode back to the mode it came from, and no two
    /// selectable values may collide.
    ///
    /// This is the invariant that the shipped ANC mapping violated: `0x02` was drawn as
    /// Transparency and commands Noise cancellation, so the pill a user pressed was not the
    /// mode they got. A round-trip per selectable value makes that class of mistake impossible
    /// to reintroduce without a failing test.
    func testEverySelectableNoiseMaskRoundTripsUniquely() {
        // Noise cancellation is reported at whichever level it is on, so its "mode" mask is
        // its High level — deliberately the same value. Uniqueness is asserted over the
        // values the UI can actually select, which is every level plus the other three modes.
        var selectable = [NoiseMode.off, .adaptive, .transparency].map(\.mask)
        selectable += ANCLevel.allCases.map(\.mask)

        XCTAssertEqual(Set(selectable).count, selectable.count,
                       "two selectable modes share a mask: \(selectable.map { String(format: "%04x", $0) })")
        XCTAssertEqual(NoiseMode.noiseCancellation.mask, ANCLevel.high.mask,
                       "Noise cancellation is stored as its High level")

        for mask in selectable + [NoiseMode.noiseCancellation.mask] {
            guard let mode = NoiseMode(mask: mask) else {
                return XCTFail("mask \(String(format: "%04x", mask)) decodes to no mode")
            }
            XCTAssertNotNil(NoiseMode(mask: mode.mask), "a mode does not decode from its own mask")
            if mode == .noiseCancellation {
                XCTAssertNotNil(ANCLevel(mask: mask), "a cancellation level does not decode")
            } else {
                XCTAssertNil(ANCLevel(mask: mask), "\(mode.label) decodes as a cancellation level")
            }
        }
    }

    /// Every gesture the editor can offer must name actions the firmware can actually store.
    /// The device validates nothing, so the restriction lives here; this asserts the
    /// restriction is at least self-consistent.
    func testGestureActionSetsAreDistinctAndNonEmpty() {
        for gesture in Gesture.allCases {
            XCTAssertFalse(gesture.actions.isEmpty, "\(gesture.label) offers no action")
            XCTAssertEqual(Set(gesture.actions.map(\.rawValue)).count, gesture.actions.count,
                           "\(gesture.label) offers the same action twice")
        }
        // A slide's meaning is volume, not track skipping: the option sets are not shared.
        XCTAssertNil(Gesture.slide.actions.first(where: { $0 == .next }))
        XCTAssertNil(Gesture.slide.actions.first(where: { $0 == .previous }))
    }

    /// The self-check binary path: a non-zero exit on failure, which is how `build.sh` and
    /// anyone else can tell without reading the output.
    func testSelfCheckResultIsNonZeroOnFailureByConstruction() {
        var failing = BudsProtocol.SelfCheckResult()
        failing.failures = ["something"]
        XCTAssertFalse(failing.passed)

        var passing = BudsProtocol.SelfCheckResult()
        passing.checks = 3
        XCTAssertTrue(passing.passed)
    }
}
