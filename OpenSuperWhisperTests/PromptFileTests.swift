import XCTest

@testable import OpenSuperWhisper

/// A prompt kept in a file overrides the one typed in Settings. The failure that matters here is
/// silent: if a missing or unreadable file returned an empty string instead of nil, it would
/// override the user's typed prompt with nothing and quietly undo their custom vocabulary.
final class PromptFileTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: String, name: String = "prompt.md") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsThePromptFromTheFile() throws {
        let url = try write("\"I'd rather not,\" she said.")
        XCTAssertEqual(Settings.promptFileContents(at: url), "\"I'd rather not,\" she said.")
    }

    func testMissingFileFallsBackRatherThanBlanking() {
        XCTAssertNil(Settings.promptFileContents(at: directory.appendingPathComponent("absent.md")),
                     "nil is what lets the typed prompt survive")
    }

    func testWhitespaceOnlyFileCountsAsAbsent() throws {
        XCTAssertNil(try Settings.promptFileContents(at: write("   \n\n  \t ")))
    }

    func testEmptyFileCountsAsAbsent() throws {
        XCTAssertNil(try Settings.promptFileContents(at: write("")))
    }

    func testSurroundingBlankLinesAreTrimmed() throws {
        XCTAssertEqual(try Settings.promptFileContents(at: write("\n\nHe said, \"go on.\"\n\n")),
                       "He said, \"go on.\"")
    }

    /// Internal newlines are the point: the sample is several lines of prose.
    func testKeepsTheShapeOfTheProse() throws {
        let prose = "\"Not tonight,\" she said.\nHe shrugged. \"Suit yourself.\""
        XCTAssertEqual(try Settings.promptFileContents(at: write(prose)), prose)
    }

    /// This is read on the dictation path, so a file pointed at something enormous must be
    /// truncated rather than pulled into memory whole.
    func testOversizedFileIsTruncatedNotRefused() throws {
        let url = try write(String(repeating: "a", count: Settings.promptFileByteLimit * 3))
        let contents = try XCTUnwrap(Settings.promptFileContents(at: url))

        XCTAssertEqual(contents.count, Settings.promptFileByteLimit)
    }

    /// A directory at the path must not throw or be read as text.
    func testDirectoryAtThePathIsIgnored() {
        XCTAssertNil(Settings.promptFileContents(at: directory))
    }

    func testInvalidUTF8IsIgnoredRatherThanMangled() throws {
        let url = directory.appendingPathComponent("bad.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: url)
        XCTAssertNil(Settings.promptFileContents(at: url))
    }
}
