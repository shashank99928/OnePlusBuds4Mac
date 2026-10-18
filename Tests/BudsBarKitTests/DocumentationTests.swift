import XCTest
@testable import BudsBarKit

/// The README and the site state numbers about this code — how many frames the corpus holds, how
/// many checks the self-check runs, how many tests there are, which version the site advertises.
/// Every one of those is a fact the code already knows, and every one of them has been wrong at
/// least once: the site still read "23 raw frames captured off the wire" two captures after that
/// stopped being true, and a comment counted six declined getters while naming four.
///
/// So they are checked here rather than trusted. This is the same contract the fixture corpus
/// works under — the hex file and the generated Swift are asserted to agree byte for byte — moved
/// to the prose, which is the part a reader has only words to go on.
final class DocumentationTests: XCTestCase {

    // MARK: - Reading the documents

    /// The repository root, from this file's own path: `Tests/BudsBarKitTests/<file>` is three
    /// directories down, and both documents live at the top of it.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func document(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// The capture groups of the first match, or nil when the sentence is gone. Returning nil for
    /// a missing sentence is deliberate: a rewrite that drops the number should fail the test, not
    /// quietly stop checking it.
    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let inner = Range(match.range(at: index), in: text) else { return "" }
            return String(text[inner])
        }
    }

    /// Test methods, counted the way the compiler sees them: a `func test…` at member indentation
    /// in one of the two test files. A loop inside a test is one test, which is what XCTest counts
    /// too.
    private func testMethodCount(in path: String) throws -> Int {
        try document(path).components(separatedBy: "\n    func test").count - 1
    }

    // MARK: - The counts

    func testTheReadmeCountsMatchTheCode() throws {
        let readme = try document("README.md")

        let frames = try XCTUnwrap(
            captures("holds\\s+(\\d+)\\s+raw RFCOMM frames", in: readme),
            "the README no longer states how many frames the corpus holds")
        XCTAssertEqual(Int(frames[0]), FixtureCorpus.frames.count,
                       "the README's frame count is stale")

        let checks = try XCTUnwrap(
            captures("exercises the wire format in\\s+(\\d+)\\s+checks", in: readme),
            "the README no longer states how many checks the self-check runs")
        let result = BudsProtocol.selfCheck()
        XCTAssertTrue(result.passed, "the self-check fails: \(result.failures)")
        XCTAssertEqual(Int(checks[0]), result.checks,
                       "the README's self-check count is stale")

        // Prose wraps, so every space in these sentences is written as `\s+`: a re-wrap must not
        // be able to stop the check by moving a line break into the middle of it.
        let tests = try XCTUnwrap(
            captures("(\\d+)\\s+tests across three classes — (\\d+)\\s+protocol tests, \\s*"
                     + "(\\d+)\\s+snapshot tests and (\\d+)\\s+documentation tests", in: readme),
            "the README no longer states how many tests there are")
        let counted = try [
            testMethodCount(in: "Tests/BudsBarKitTests/ProtocolTests.swift"),
            testMethodCount(in: "Tests/BudsBarKitTests/SnapshotTests.swift"),
            testMethodCount(in: "Tests/BudsBarKitTests/DocumentationTests.swift"),
        ]
        XCTAssertEqual(Int(tests[1]), counted[0], "the README's protocol test count is stale")
        XCTAssertEqual(Int(tests[2]), counted[1], "the README's snapshot test count is stale")
        XCTAssertEqual(Int(tests[3]), counted[2], "the README's documentation test count is stale")
        XCTAssertEqual(Int(tests[0]), counted.reduce(0, +),
                       "the README's total does not add up to its own classes")
    }

    func testTheSiteCountsAndVersionMatchTheCode() throws {
        let site = try document("docs/index.html")

        let frames = try XCTUnwrap(
            captures("(\\d+)\\s+raw frames captured off the wire", in: site),
            "the site no longer states how many frames were captured")
        XCTAssertEqual(Int(frames[0]), FixtureCorpus.frames.count,
                       "the site's frame count is stale")

        // The site advertises a version, and it is the one the bundle is built with. A release
        // that bumps the plist and forgets the page is how a visitor downloads 1.1.3 and reads
        // about 1.1.2.
        let advertised = try XCTUnwrap(
            captures("\"softwareVersion\": \"([0-9.]+)\"", in: site),
            "the site no longer advertises a version")
        let plist = try document("Resources/Info.plist")
        let bundled = try XCTUnwrap(
            captures("CFBundleShortVersionString</key>\\s*<string>([0-9.]+)</string>", in: plist),
            "the bundle version could not be read")
        XCTAssertEqual(advertised[0], bundled[0],
                       "the site advertises a different version than the bundle builds")
    }
}
