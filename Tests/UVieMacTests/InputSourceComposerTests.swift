import Cocoa
import XCTest
@testable import UVieMac

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

    /// Feed every character through a FRESH client wrapper per key around
    /// one shared field - the same per-key adapter lifetime the production
    /// IMK path has (`UVieInputController` creates a new `IMKClientAdapter`
    /// for each event, so the composer can never retain one).
    private func typePerKey(_ s: String, _ composer: InputSourceComposer,
                            _ store: TextFieldStore, bundleID: String = "com.test.fake") {
        for ch in s {
            let client = FakeTextClient(store: store, bundleID: bundleID)
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

    func test_plainStyle_marksWithoutUnderline_markedStyleUnderlines() {
        let plain = makeComposer(style: "plain")
        let plainClient = FakeTextClient()
        type("vie", plain, plainClient)
        XCTAssertEqual(plainClient.underlinedFlags.last, false)

        let marked = makeComposer(style: "marked")
        let markedClient = FakeTextClient()
        type("vie", marked, markedClient)
        XCTAssertEqual(markedClient.underlinedFlags.last, true)
    }

    /// Every render style covered by the same typing expectations.
    private func forBothStyles(_ body: (InputSourceComposer, FakeTextClient) -> Void) {
        for style in ["marked", "plain", "direct"] {
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

    // MARK: - Settings changes mid-session

    /// Switching the language off mid-word finalizes what is shown and the
    /// next keys type natively - no character lost or duplicated. Every key
    /// arrives through a fresh client wrapper: a settings reload can never
    /// finalize through the client that typed the word, because none is
    /// retained.
    func test_languageOffMidWord_bothStyles() {
        for style in ["marked", "direct"] {
            let composer = makeComposer(style: style)
            let store = TextFieldStore()
            typePerKey("vieej", composer, store)
            XCTAssertEqual(FakeTextClient(store: store).text, "việ")
            UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
            composer.reloadSettings()
            typePerKey("t ", composer, store)
            XCTAssertEqual(FakeTextClient(store: store).text, "việt ")
            UserDefaults.standard.set(true, forKey: DefaultsKey.engineEnabled)
        }
    }

    /// Focus loss right after the settings flip: the deferred finalize must
    /// still write the shown word exactly once.
    func test_abandonWordAfterLanguageOff_freshClient() {
        let composer = makeComposer(style: "marked")
        let store = TextFieldStore()
        typePerKey("vieej", composer, store)
        UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
        composer.reloadSettings()
        composer.abandonWord(FakeTextClient(store: store))
        XCTAssertEqual(FakeTextClient(store: store).text, "việ")
        composer.abandonWord(FakeTextClient(store: store))
        XCTAssertEqual(FakeTextClient(store: store).text, "việ")
        UserDefaults.standard.set(true, forKey: DefaultsKey.engineEnabled)
    }

    /// Language off then on again before any key: the deferred finalize
    /// still fires once on the next key, and that key starts a fresh word.
    func test_languageOffThenOnBeforeKey_finalizesOnce() {
        let composer = makeComposer(style: "marked")
        let store = TextFieldStore()
        typePerKey("vieej", composer, store)
        UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
        composer.reloadSettings()
        UserDefaults.standard.set(true, forKey: DefaultsKey.engineEnabled)
        composer.reloadSettings()
        typePerKey("t ", composer, store)
        XCTAssertEqual(FakeTextClient(store: store).text, "việt ")
    }

    /// Switching the input method mid-word finalizes the half-typed word as
    /// shown, and the next word obeys the new method.
    func test_methodSwitchMidWord_flushesAndUsesNewMethod() {
        for style in ["marked", "direct"] {
            let composer = makeComposer(style: style)
            let store = TextFieldStore()
            typePerKey("tiee", composer, store)
            XCTAssertEqual(FakeTextClient(store: store).text, "tiê")
            UserDefaults.standard.set("vni", forKey: DefaultsKey.inputMethod)
            composer.reloadSettings()
            typePerKey("a1 ", composer, store)
            XCTAssertEqual(FakeTextClient(store: store).text, "tiêá ")
            UserDefaults.standard.set("telex", forKey: DefaultsKey.inputMethod)
        }
    }

    /// Changing the display style between words takes effect on the next
    /// word: the word typed after a marked -> direct switch has no marked
    /// text, and the reverse leaves marked text on screen.
    func test_styleSwitchAppliesToNextWord() {
        UserDefaults.standard.set("marked", forKey: DefaultsKey.inputSourceStyle)
        let composer = InputSourceComposer()
        let client = FakeTextClient()
        type("vieetj ", composer, client)
        XCTAssertEqual(client.text, "việt ")

        UserDefaults.standard.set("direct", forKey: DefaultsKey.inputSourceStyle)
        composer.reloadSettings()
        type("nam ", composer, client)
        XCTAssertEqual(client.text, "việt nam ")
        XCTAssertNil(client.markedRange, "direct style must not leave marked text")

        UserDefaults.standard.set("marked", forKey: DefaultsKey.inputSourceStyle)
        composer.reloadSettings()
        type("viee", composer, client)
        XCTAssertEqual(client.text, "việt nam viê")
        XCTAssertNotNil(client.markedRange)
    }

    /// Switching style mid-word finalizes the shown word first; the next
    /// key starts a fresh word under the new style. Per-key wrappers
    /// exercise the deferred finalize path for the marked side.
    func test_styleSwitchMidWord_finalizesShownWord() {
        // marked -> direct: "vie" becomes final text, 'e' starts a new
        // direct word appended at the caret.
        var composer = makeComposer(style: "marked")
        var store = TextFieldStore()
        typePerKey("vie", composer, store)
        XCTAssertEqual(FakeTextClient(store: store).text, "vie")
        UserDefaults.standard.set("direct", forKey: DefaultsKey.inputSourceStyle)
        composer.reloadSettings()
        typePerKey("e", composer, store)
        XCTAssertEqual(FakeTextClient(store: store).text, "viee")

        // direct -> marked: "vie" is already final text, 'e' becomes a
        // fresh marked word.
        composer = makeComposer(style: "direct")
        store = TextFieldStore()
        typePerKey("vie", composer, store)
        XCTAssertEqual(FakeTextClient(store: store).text, "vie")
        UserDefaults.standard.set("marked", forKey: DefaultsKey.inputSourceStyle)
        composer.reloadSettings()
        typePerKey("e", composer, store)
        let lastClient = FakeTextClient(store: store)
        XCTAssertEqual(lastClient.text, "viee")
        XCTAssertNotNil(lastClient.markedRange)
    }

    /// Modern orthography moves the tone mark between the two vowel forms.
    func test_modernOrthographyToggle_bothStyles() {
        for modern in [true, false] {
            UserDefaults.standard.set(modern, forKey: DefaultsKey.modernOrthography)
            forBothStyles { composer, client in
                type("hoaf ", composer, client)
                XCTAssertEqual(client.text, modern ? "hoà " : "hòa ")
            }
        }
    }

    /// A bundle ID added to the excluded list stops composing while other
    /// apps keep working.
    func test_excludedAppAdded_bothStyles() {
        UserDefaults.standard.set(["com.test.excluded"], forKey: DefaultsKey.customExcludedApps)
        forBothStyles { composer, _ in
            let excluded = FakeTextClient(bundleID: "com.test.excluded")
            type("vieetj ", composer, excluded)
            XCTAssertEqual(excluded.text, "vieetj ")
            let normal = FakeTextClient(bundleID: "com.test.other")
            type("vieetj ", composer, normal)
            XCTAssertEqual(normal.text, "việt ")
        }
    }

    // MARK: - Navigation and non-text keys

    /// A caret-moving key commits the shown word and the next word starts
    /// fresh - the old word is never re-transformed.
    private func assertFlushKey(keyCode: UInt16, file: StaticString = #filePath, line: UInt = #line) {
        forBothStyles { composer, client in
            type("vieet", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: keyCode, characters: nil,
                              command: false, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed, "keyCode \(keyCode)", file: file, line: line)
            XCTAssertEqual(client.text, "viêt", file: file, line: line)
            XCTAssertNil(client.markedRange, file: file, line: line)
            type("nam ", composer, client)
            XCTAssertEqual(client.text, "viêtnam ", file: file, line: line)
        }
    }

    func test_arrowKey_flushesAndPassesThrough() { assertFlushKey(keyCode: 123) }
    func test_tab_flushesAndPassesThrough() { assertFlushKey(keyCode: 48) }
    func test_home_flushesAndPassesThrough() { assertFlushKey(keyCode: 115) }
    func test_forwardDelete_flushesAndPassesThrough() { assertFlushKey(keyCode: 117) }

    func test_optionAndControlKeys_flushAndPassThrough() {
        forBothStyles { composer, client in
            type("vieet", composer, client)
            // Option+key produces a glyph the engine never saw.
            XCTAssertFalse(composer.handle(
                key: KeyInput(keyCode: 4, characters: "´", command: false, control: false, option: true),
                client: client))
            client.nativeInsert("´")
            XCTAssertEqual(client.text, "viêt´")
            // Control+key is an app shortcut.
            type("vieet", composer, client)
            XCTAssertFalse(composer.handle(
                key: KeyInput(keyCode: 8, characters: "c", command: false, control: true, option: false),
                client: client))
            XCTAssertEqual(client.text, "viêt´viêt")
        }
    }

    /// A non-ASCII character key mid-word finalizes the composition and
    /// types natively - the engine only understands ASCII.
    func test_nonAsciiKeyMidWord_bothStyles() {
        forBothStyles { composer, client in
            type("viee", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 0, characters: "é", command: false, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed)
            client.nativeInsert("é")
            // The flush finalizes the shown word as-is - "viê" stays.
            XCTAssertEqual(client.text, "viêé")
        }
    }

    // MARK: - Text variety

    func test_digits_bothMethods() {
        forBothStyles { composer, client in
            type("nawm 2026 ", composer, client)
            XCTAssertEqual(client.text, "năm 2026 ")
        }
        UserDefaults.standard.set("vni", forKey: DefaultsKey.inputMethod)
        forBothStyles { composer, client in
            type("2026 ", composer, client)
            XCTAssertEqual(client.text, "2026 ")
        }
    }

    func test_uppercaseAndCaps_bothStyles() {
        forBothStyles { composer, client in
            type("VIEETJ ", composer, client)
            XCTAssertEqual(client.text, "VIỆT ")
        }
        forBothStyles { composer, client in
            type("Vieetj ", composer, client)
            XCTAssertEqual(client.text, "Việt ")
        }
    }

    func test_doubleSpaceAndPunctuation_bothStyles() {
        forBothStyles { composer, client in
            type("xin  ", composer, client)
            XCTAssertEqual(client.text, "xin  ")
        }
        forBothStyles { composer, client in
            type("xin, chaof", composer, client)
            XCTAssertEqual(client.text, "xin, chào")
        }
    }

    /// Escape on a word whose render equals its raw keystrokes has nothing
    /// to restore - the key passes through.
    func test_escapeWithNothingToRestore_bothStyles() {
        forBothStyles { composer, client in
            type("abc", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 53, characters: nil,
                              command: false, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed)
            XCTAssertEqual(client.text, "abc")
        }
    }

    /// Backspace at idle is a native delete; typing afterwards does not
    /// re-open the committed word (post-commit editing is not supported in
    /// this mode).
    func test_backspaceAtIdle_thenTypingDoesNotReopenWord_bothStyles() {
        forBothStyles { composer, client in
            type("viet ", composer, client)
            XCTAssertEqual(client.text, "viet ")
            let consumed = composer.handle(
                key: KeyInput(keyCode: 51, characters: nil,
                              command: false, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed, "idle backspace must delete natively")
            client.nativeBackspace()
            XCTAssertEqual(client.text, "viet")
            type("j", composer, client)
            // 'j' passes through natively - the committed word stays put.
            XCTAssertEqual(client.text, "vietj")
        }
    }

    /// A long word outgrowing the raw buffer types through unchanged.
    func test_longIdentifier_bothStyles() {
        forBothStyles { composer, client in
            type("abcdefghijklmnopqrstuvwxyzabcd ", composer, client)
            XCTAssertEqual(client.text, "abcdefghijklmnopqrstuvwxyzabcd ")
        }
    }

    /// commitComposition/deactivateServer finalizes the shown text exactly
    /// once - calling abandonWord twice must not duplicate it.
    func test_abandonWordTwice_doesNotDuplicate_bothStyles() {
        forBothStyles { composer, client in
            type("vieet", composer, client)
            composer.abandonWord(client)
            XCTAssertEqual(client.text, "viêt")
            composer.abandonWord(client)
            XCTAssertEqual(client.text, "viêt")
        }
    }

    /// A flush keeps the shown word even when the engine's commit rules
    /// would restore raw keys: "việ" stays "việ", never "vieej".
    func test_commandChord_keepsShownWord_bothStyles() {
        forBothStyles { composer, client in
            type("vieej", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 0, characters: "a",
                              command: true, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed, "Cmd+A is an app shortcut")
            XCTAssertEqual(client.text, "việ")
            XCTAssertNil(client.markedRange)
        }
    }

    /// Same for a caret-moving key: the shown render is final.
    func test_arrowKey_keepsShownWord_bothStyles() {
        forBothStyles { composer, client in
            type("vieej", composer, client)
            let consumed = composer.handle(
                key: KeyInput(keyCode: 123, characters: nil,
                              command: false, control: false, option: false),
                client: client)
            XCTAssertFalse(consumed)
            XCTAssertEqual(client.text, "việ")
        }
    }

    /// abandonWord on an incomplete word keeps the shown render.
    func test_abandonWord_incompleteWordKeepsShown_bothStyles() {
        forBothStyles { composer, client in
            type("vieej", composer, client)
            composer.abandonWord(client)
            XCTAssertEqual(client.text, "việ")
            composer.abandonWord(client)
            XCTAssertEqual(client.text, "việ")
        }
    }

    /// An English word the engine rendered with accents is restored to its
    /// real spelling at the word boundary - the same rewrite the tap posts.
    func test_englishRestoreAtBoundary_bothStyles() {
        forBothStyles { composer, client in
            type("test ", composer, client)
            XCTAssertEqual(client.text, "test ")
        }
    }

    /// Reloading settings when nothing changed must not touch a live word:
    /// the IM process reloads on every unrelated defaults notification.
    func test_reloadSettingsNoChange_preservesWord_bothStyles() {
        forBothStyles { composer, client in
            type("vie", composer, client)
            composer.reloadSettings()
            type("etj ", composer, client)
            XCTAssertEqual(client.text, "việt ")
        }
    }

    // MARK: - Direct-mode edge cases

    /// A client with an active selection: replacing into it is unsafe, so
    /// the key passes through and the app drops to marked-text fallback.
    func test_direct_selectionPresent_keyPassesThrough() {
        let composer = makeComposer(style: "direct")
        let client = FakeTextClient()
        client.nativeInsert("abc")
        client.select(2)
        let consumed = composer.handle(key: charKey("x"), client: client)
        XCTAssertFalse(consumed)
        client.nativeInsert("x") // a real app types over the selection
        XCTAssertEqual(client.text, "ax")
        XCTAssertTrue(composer.directUnsupported.contains(client.clientBundleID))
    }

    /// The user moved the caret between two keys of a word: the replacement
    /// must never touch text outside the word, so the key passes through
    /// and the app falls back to marked text.
    func test_direct_caretMovedMidWord_passesThrough() {
        let composer = makeComposer(style: "direct")
        let client = FakeTextClient()
        type("vie", composer, client)
        XCTAssertEqual(client.text, "vie")
        client.moveCaret(to: 0)
        let consumed = composer.handle(key: charKey("e"), client: client)
        XCTAssertFalse(consumed)
        client.nativeInsert("e")
        XCTAssertEqual(client.text, "evie")
        XCTAssertTrue(composer.directUnsupported.contains(client.clientBundleID))
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
