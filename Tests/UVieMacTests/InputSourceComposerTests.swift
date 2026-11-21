import Cocoa
import XCTest
@testable import UVieMac

// MARK: - Fake text field

/// Models a real text field for `InputSourceComposer`: UTF-16 storage, a
/// caret, and an optional marked range. `setMarkedText` replaces the marked
/// range (or inserts at the caret) and keeps it marked; `insertText` with
/// NSNotFound replaces the marked range if any, else inserts at the caret;
/// with a real range it replaces that UTF-16 range. `selectedRange` returns
/// the caret.
class FakeTextClient: TextInputClient {
    var clientBundleID: String
    private(set) var utf16 = [UInt16]()
    private(set) var caret = 0
    private(set) var markedRange: Range<Int>?

    var text: String {
        String(String(decoding: utf16, as: UTF16.self))
    }

    init(bundleID: String = "com.test.fake") {
        self.clientBundleID = bundleID
    }

    func selectedRange() -> NSRange {
        NSRange(location: caret, length: 0)
    }

    func setMarkedText(_ text: String) {
        let units = Array(text.utf16)
        if let markedRange {
            utf16.replaceSubrange(markedRange, with: units)
            caret = markedRange.lowerBound + units.count
            self.markedRange = units.isEmpty
                ? nil
                : markedRange.lowerBound..<(markedRange.lowerBound + units.count)
        } else {
            utf16.insert(contentsOf: units, at: caret)
            markedRange = units.isEmpty ? nil : caret..<(caret + units.count)
            caret += units.count
        }
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        let units = Array(text.utf16)
        if replacementRange.location == NSNotFound {
            if let markedRange {
                utf16.replaceSubrange(markedRange, with: units)
                caret = markedRange.lowerBound + units.count
                self.markedRange = nil
            } else {
                utf16.insert(contentsOf: units, at: caret)
                caret += units.count
            }
        } else {
            let range = replacementRange.location..<(replacementRange.location + replacementRange.length)
            utf16.replaceSubrange(range, with: units)
            caret = range.lowerBound + units.count
            markedRange = nil
        }
    }

    /// The character the app types itself when the composer lets the key
    /// through.
    func nativeInsert(_ s: String) {
        let units = Array(s.utf16)
        utf16.insert(contentsOf: units, at: caret)
        caret += units.count
    }

    /// A native backspace: delete one UTF-16 unit before the caret.
    func nativeBackspace() {
        guard caret > 0 else { return }
        utf16.remove(at: caret - 1)
        caret -= 1
    }
}

/// A client whose `selectedRange` reports the caret one call stale - some
/// apps update the selection asynchronously after `insertText`.
final class LaggingClient: FakeTextClient {
    private var lastReported = 0
    override func selectedRange() -> NSRange {
        defer { lastReported = caret }
        return NSRange(location: lastReported, length: 0)
    }
}

/// A client that ignores `replacementRange` and always inserts at the caret.
final class IgnoringClient: FakeTextClient {
    override func insertText(_ text: String, replacementRange: NSRange) {
        super.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

// MARK: - Composer tests

final class InputSourceComposerTests: XCTestCase {
    private var savedDefaults: [String: Any?] = [:]
    private let savedDefaultsKeys = [
        DefaultsKey.engineEnabled,
        DefaultsKey.inputMethod,
        DefaultsKey.modernOrthography,
        DefaultsKey.relaxedCoda,
        DefaultsKey.quickTelex,
        DefaultsKey.quickStart,
        DefaultsKey.checkSpelling,
        DefaultsKey.macroEnabled,
        DefaultsKey.inputSourceStyle,
        DefaultsKey.customExcludedApps,
        DefaultsKey.customBypassApps,
        DefaultsKey.removedBypassApps,
        "Macros",
    ]

    override func setUp() {
        super.setUp()
        for key in savedDefaultsKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        // Pin the environment: a composer's settings all come through
        // UserDefaults, so tests must not depend on the user's real values.
        UserDefaults.standard.set(true, forKey: DefaultsKey.engineEnabled)
        UserDefaults.standard.set("telex", forKey: DefaultsKey.inputMethod)
        UserDefaults.standard.set(true, forKey: DefaultsKey.modernOrthography)
        UserDefaults.standard.set(false, forKey: DefaultsKey.relaxedCoda)
        UserDefaults.standard.set(false, forKey: DefaultsKey.quickTelex)
        UserDefaults.standard.set(false, forKey: DefaultsKey.quickStart)
        UserDefaults.standard.set(true, forKey: DefaultsKey.checkSpelling)
        UserDefaults.standard.set("marked", forKey: DefaultsKey.inputSourceStyle)
        UserDefaults.standard.set([], forKey: DefaultsKey.customExcludedApps)
        UserDefaults.standard.set([], forKey: DefaultsKey.customBypassApps)
        UserDefaults.standard.set([], forKey: DefaultsKey.removedBypassApps)
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedDefaults = [:]
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeComposer(style: String) -> InputSourceComposer {
        UserDefaults.standard.set(style, forKey: DefaultsKey.inputSourceStyle)
        return InputSourceComposer()
    }

    private func charKey(_ ch: Character) -> KeyInput {
        KeyInput(keyCode: 0, characters: String(ch), command: false, control: false, option: false)
    }

    /// Feed every character; a key the composer declines types natively.
    private func type(_ s: String, _ composer: InputSourceComposer, _ client: FakeTextClient) {
        for ch in s {
            if !composer.handle(key: charKey(ch), client: client) {
                client.nativeInsert(String(ch))
            }
        }
    }

    /// Feed a key the composer should decline; types natively when it does.
    private func sendNative(_ key: KeyInput, _ composer: InputSourceComposer,
                            _ client: FakeTextClient, native: (() -> Void)? = nil) -> Bool {
        let consumed = composer.handle(key: key, client: client)
        if !consumed { native?() }
        return consumed
    }

    private func backspaceKey() -> KeyInput {
        KeyInput(keyCode: 51, characters: nil, command: false, control: false, option: false)
    }

    // MARK: - Cases

    /// Every render style covered by the same typing expectations.
    private func forBothStyles(_ body: (InputSourceComposer, FakeTextClient) -> Void) {
        for style in ["marked", "direct"] {
            let composer = makeComposer(style: style)
            body(composer, FakeTextClient())
        }
    }

    func test_telexSentence_bothStyles() {
        forBothStyles { composer, client in
            type("tieengs vieetj ", composer, client)
            XCTAssertEqual(client.text, "tiếng việt ")
        }
    }

    func test_duoc_bothStyles() {
        forBothStyles { composer, client in
            type("dduowcj ", composer, client)
            XCTAssertEqual(client.text, "được ")
        }
    }

    func test_vni_bothStyles() {
        UserDefaults.standard.set("vni", forKey: DefaultsKey.inputMethod)
        forBothStyles { composer, client in
            type("tieng61 ", composer, client)
            XCTAssertEqual(client.text, "tiếng ")
        }
    }

    func test_midWord_markedShowsMarkedText() {
        let composer = makeComposer(style: "marked")
        let client = FakeTextClient()
        type("tieengs", composer, client)
        XCTAssertEqual(composer.composingText, "tiếng")
        XCTAssertEqual(client.text, "tiếng")
        XCTAssertNotNil(client.markedRange)
    }

    func test_midWord_directHasNoMarkedText() {
        let composer = makeComposer(style: "direct")
        let client = FakeTextClient()
        type("tieengs", composer, client)
        XCTAssertEqual(client.text, "tiếng")
        XCTAssertNil(client.markedRange)
        XCTAssertEqual(composer.composingText, "")
    }

    func test_backspace_bothStyles() {
        forBothStyles { composer, client in
            type("vieetj", composer, client)
            _ = composer.handle(key: backspaceKey(), client: client)
            _ = composer.handle(key: backspaceKey(), client: client)
            type("j", composer, client)
            // Expected = the same key sequence replayed through a bare engine.
            let engine = EngineBridge()
            engine.setInputMethod(.telex)
            for ch in "vieetj" { _ = engine.feed(char: ch) }
            _ = engine.backspace()
            _ = engine.backspace()
            _ = engine.feed(char: "j")
            XCTAssertEqual(client.text, engine.committedText() + engine.currentOutput())
        }
    }

    func test_englishWords_bothStyles() {
        forBothStyles { composer, client in
            type("master ", composer, client)
            XCTAssertEqual(client.text, "master ")
        }
        forBothStyles { composer, client in
            type("character ", composer, client)
            XCTAssertEqual(client.text, "character ")
        }
    }

    func test_commandKeyFlushes_bothStyles() {
        forBothStyles { composer, client in
            type("vieet", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 0, characters: "a", command: true, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed)
            XCTAssertEqual(client.text, "viêt")
            XCTAssertEqual(composer.composingText, "")
            XCTAssertFalse(composer.engine.isComposing)
        }
    }

    func test_escapeRestoresRaw_bothStyles() {
        forBothStyles { composer, client in
            type("vieet", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 53, characters: nil, command: false, control: false, option: false),
                client: client)
            XCTAssertTrue(consumed)
            XCTAssertEqual(client.text, "vieet")
        }
    }

    func test_vietnameseOffPassesEverything() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
        let composer = InputSourceComposer()
        let client = FakeTextClient()
        for ch in "vieetj " {
            let consumed = composer.handle(key: charKey(ch), client: client)
            XCTAssertFalse(consumed, "key '\(ch)' must pass through")
            client.nativeInsert(String(ch))
        }
        XCTAssertEqual(client.text, "vieetj ")
    }

    func test_excludedAppPassesEverything() {
        UserDefaults.standard.set(["com.test.fake"], forKey: DefaultsKey.customExcludedApps)
        let composer = InputSourceComposer()
        let client = FakeTextClient(bundleID: "com.test.fake")
        for ch in "vieetj " {
            let consumed = composer.handle(key: charKey(ch), client: client)
            XCTAssertFalse(consumed, "key '\(ch)' must pass through")
            client.nativeInsert(String(ch))
        }
        XCTAssertEqual(client.text, "vieetj ")
    }

    func test_punctuationCommit_bothStyles() {
        forBothStyles { composer, client in
            type("xin chaof, banj!", composer, client)
            XCTAssertEqual(client.text, "xin chào, bạn!")
        }
    }

    func test_enterCommitsAndPassesThrough_bothStyles() {
        forBothStyles { composer, client in
            type("vieetj", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 36, characters: "\r", command: false, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed, "Enter must pass through so the app makes a newline")
            XCTAssertEqual(client.text, "việt")
        }
    }

    func test_directLaggingClientFallsBackToMarked() {
        let composer = makeComposer(style: "direct")
        let client = LaggingClient()
        type("tieengs vieetj ", composer, client)
        XCTAssertTrue(composer.directUnsupported.contains(client.clientBundleID))
        XCTAssertNil(client.markedRange)
        XCTAssertTrue(client.text.hasSuffix("việt "), "got: \(client.text)")
    }

    func test_directIgnoringClientFallsBackToMarked() {
        let composer = makeComposer(style: "direct")
        let client = IgnoringClient()
        type("tieengs vieetj ", composer, client)
        XCTAssertTrue(composer.directUnsupported.contains(client.clientBundleID))
        XCTAssertTrue(client.text.hasSuffix("việt "), "got: \(client.text)")
    }

    func test_macroExpansionOnSpace_bothStyles() {
        let manager = MacroManager.shared
        let originalMacros = manager.macros
        let originalEnabled = manager.enabledCache
        defer {
            manager.macros = originalMacros
            manager.enabledCache = originalEnabled
        }
        manager.macros = [MacroManager.Macro(abbreviation: "gtn", expansion: "gõ tắt nhanh")]
        // Both layers: the defaults key covers the (async) cache refresh the
        // didChangeNotification fires, the cache covers isEnabled() reads
        // that run before it lands.
        UserDefaults.standard.set(true, forKey: DefaultsKey.macroEnabled)
        manager.enabledCache = true

        forBothStyles { composer, client in
            type("gtn", composer, client)
            // The matching word is replaced by the expansion and the space
            // key passes through to type natively.
            let consumed = composer.handle(key: charKey(" "), client: client)
            XCTAssertFalse(consumed)
            client.nativeInsert(" ")
            XCTAssertEqual(client.text, "gõ tắt nhanh ")
        }
    }
}

// MARK: - Installer (pure parts)

final class InputSourceInstallerTests: XCTestCase {
    /// Make a minimal fake .app bundle with the given CFBundleVersion.
    private func makeBundle(version: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("FakeIM.app")
        let contents = dir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleVersion": version]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return dir
    }

    func test_needsUpdate_versionComparison() throws {
        let bundledV1 = try makeBundle(version: "100")
        let installedV1 = try makeBundle(version: "100")
        let installedV2 = try makeBundle(version: "200")
        let missing = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString).app")

        XCTAssertFalse(InputSourceInstaller.needsUpdate(bundled: bundledV1, installed: installedV1))
        XCTAssertTrue(InputSourceInstaller.needsUpdate(bundled: bundledV1, installed: installedV2))
        XCTAssertFalse(InputSourceInstaller.needsUpdate(bundled: bundledV1, installed: missing),
                       "a missing installed copy is an install, not an update")

        try? FileManager.default.removeItem(at: bundledV1.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: installedV1.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: installedV2.deletingLastPathComponent())
    }

    func test_bundledURL_envVarFallback() throws {
        let bundle = try makeBundle(version: "1")
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        setenv("UVIE_IM_BUNDLE", bundle.path, 1)
        defer { unsetenv("UVIE_IM_BUNDLE") }
        XCTAssertEqual(InputSourceInstaller.bundledURL?.path, bundle.path)

        setenv("UVIE_IM_BUNDLE", "/tmp/definitely-not-here-\(UUID().uuidString).app", 1)
        XCTAssertNil(InputSourceInstaller.bundledURL,
                     "a nonexistent env path must not be used")
    }
}
