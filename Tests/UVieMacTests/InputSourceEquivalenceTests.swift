import Cocoa
import XCTest
@testable import UVieMac

/// Equivalence: typing the same keystrokes through the event tap (synthetic
/// backspaces + reposts, replayed into `TextFieldModel`) and through the
/// input source (`InputSourceComposer` + `FakeTextClient`) must produce the
/// same text on screen. The input-source path is what users see when the
/// UVieIM input method is selected; the tap path is the shipped behavior.
final class InputSourceEquivalenceTests: XCTestCase {
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

    // MARK: - Corpus

    /// Vietnamese sentences (Telex keystrokes).
    static let corpusA = [
        "xin chaof cacs banj, hoom nay trowif ddepj quas!",
        "tooi ddang hocj tieengs Vieetj owr Haf Nooij.",
        "khoong cos gif quys hown ddoocj laapj tuwj do",
        "muoons nhanh thif phair tuwf tuwf",
        "uoongs nuwowcs nhows nguoonf",
        "Nguyeenx Vawn A ddax guiwr thuw cho banj roofi.",
        "gias xawng tawng 5% trong thangs 12 nawm 2026.",
        "TIEENGS VIEEJT COS DAAUS",
        "giwx gif thif giwx, dduwngf ddeer maast",
    ]

    /// Mixed / English sentences (Telex keystrokes).
    static let corpusB = [
        "cais nafy laf master branch, ddungwf deploy server nhes.",
        "fix bug jira xong chuwa, check giups minhf",
        "the quick brown fox jumps over the lazy dog",
        "this is the best password for my business",
    ]

    /// Vietnamese sentences (VNI keystrokes).
    static let corpusC = [
        "to6i d9ang ho5c tie61ng Vie65t",
        "nguoi72 ta noi1 rang82 khong6 sao",
        "d9uong72 ve62 que6 xa lam81",
        "tieng61 Viet65 co1 dau61",
    ]

    // MARK: - Replay helpers

    /// US-layout virtual key codes for the characters the corpus uses.
    /// Letters/digits map to their physical key; shifted characters reuse
    /// the base key with `.maskShift`.
    private static let keyCodes: [Character: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ",": 43, ".": 47, "/": 44, " ": 49,
    ]

    /// The physical key an upper-case / shifted character is typed on.
    private static let shiftedKeyCodes: [Character: Int64] = [
        "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26,
        "*": 28, "(": 25, ")": 29, "?": 44, ":": 41, "\"": 39,
    ]

    /// Send one key through `EventTap.handle` and apply whatever happened
    /// to the field: recorded injection calls first, then the native edit
    /// when the key itself passed through.
    private func tapSend(_ tap: EventTap, _ sink: RecordingSink, _ field: inout TextFieldModel,
                         keyCode: Int64, flags: CGEventFlags = [], unicode: String? = nil) {
        let passed = send(tap, .keyDown, keyDownEvent(keyCode, flags: flags, unicode: unicode))
        for call in sink.calls { field.apply(call) }
        sink.reset()
        guard let passed else { return }
        passed.release()
        // The key reaches the app natively.
        switch keyCode {
        case 51: field.backspace(1)
        case 117: field.forwardDelete(1)
        case 36, 76: field.insert("\n")
        case 49: field.insert(" ")
        case 48: field.insert("\t")
        default:
            if let unicode {
                for ch in unicode { field.insert(ch) }
            }
        }
    }

    /// Replay keystrokes through the event tap the way `DispatcherTests`
    /// drives `handle()`, applying every recorded call to `TextFieldModel`.
    private func typeThroughTap(_ keys: String, method: InputMethod) -> String {
        let tap = makeEventTap()
        tap._engine.setInputMethod(method)
        let sink = RecordingSink()
        tap.outputSink = sink
        var field = TextFieldModel()
        for ch in keys {
            let shifted = ch.isUppercase || Self.shiftedKeyCodes[ch] != nil
            guard let code = Self.keyCodes[ch.lowercased().first ?? ch]
                    ?? Self.shiftedKeyCodes[ch] else {
                XCTFail("no key code for '\(ch)'")
                continue
            }
            tapSend(tap, sink, &field, keyCode: code,
                    flags: shifted ? [.maskShift] : [], unicode: String(ch))
        }
        return field.text
    }

    /// Press Backspace through the tap once (consumed or native).
    private func tapBackspace(_ tap: EventTap, _ sink: RecordingSink, _ field: inout TextFieldModel) {
        tapSend(tap, sink, &field, keyCode: 51)
    }

    /// Replay keystrokes through the input source into a `FakeTextClient`.
    /// A key the composer declines types natively, exactly like the real
    /// client-side text field.
    private func typeThroughInputSource(_ keys: String, method: InputMethod,
                                        style: String, client: FakeTextClient = FakeTextClient()) -> String {
        UserDefaults.standard.set(method.rawValue, forKey: DefaultsKey.inputMethod)
        UserDefaults.standard.set(style, forKey: DefaultsKey.inputSourceStyle)
        let composer = InputSourceComposer()
        for ch in keys {
            let key = KeyInput(keyCode: inputSourceKeyCode(for: ch),
                               characters: String(ch),
                               command: false, control: false, option: false)
            if !composer.handle(key: key, client: client) {
                client.nativeInsert(String(ch))
            }
        }
        return client.text
    }

    /// The physical key code for a character, as `UInt16` for `KeyInput`.
    private func inputSourceKeyCode(for ch: Character) -> UInt16 {
        let code = Self.keyCodes[ch.lowercased().first ?? ch] ?? Self.shiftedKeyCodes[ch] ?? 0
        return UInt16(clamping: code)
    }

    /// Press Backspace through the composer once (drain or native delete).
    private func composerBackspace(_ composer: InputSourceComposer, _ client: FakeTextClient) {
        let key = KeyInput(keyCode: 51, characters: nil,
                           command: false, control: false, option: false)
        if !composer.handle(key: key, client: client) {
            client.nativeBackspace()
        }
    }

    // MARK: - Equivalence

    /// Sentences where marked style legitimately diverges from the tap: the
    /// tap applies a cross-word retro rewrite (English restore reaching into
    /// earlier committed words) that marked text cannot honor, so the
    /// composer commits the word as shown instead. Asserted exactly in
    /// `test_markedStyle_keepsShownWord_whenEngineRewritesEarlierWords`.
    static let markedDivergent = Set([
        "this is the best password for my business",
    ])

    private func assertEquivalent(_ sentences: [String], method: InputMethod,
                                  file: StaticString = #filePath, line: UInt = #line) {
        for keys in sentences {
            let typed = keys + " "
            let viaTap = typeThroughTap(typed, method: method)
            for style in ["marked", "direct"] {
                if style == "marked", Self.markedDivergent.contains(keys) { continue }
                let viaIM = typeThroughInputSource(typed, method: method, style: style)
                XCTAssertEqual(viaIM, viaTap,
                               "style \(style) diverged on input: \(typed)",
                               file: file, line: line)
            }
        }
    }

    func test_equivalence_corpusA_telex() {
        assertEquivalent(Self.corpusA, method: .telex)
    }

    func test_equivalence_corpusB_telex() {
        assertEquivalent(Self.corpusB, method: .telex)
    }

    /// Marked style cannot honor a commit that rewrites the word's whole
    /// render (English dictionary restore reports more backspaces than the
    /// marked text has chars). The composer deliberately commits the shown
    /// word and drops the engine's history, so the field keeps "thí í …
    /// bét" while the tap restores the English spellings. Direct style
    /// rewrites the range in place and matches the tap.
    func test_markedStyle_keepsShownWord_whenEngineRewritesEarlierWords() {
        let keys = "this is the best password for my business "
        XCTAssertEqual(typeThroughTap(keys, method: .telex),
                       "this is the best password for my business ")
        XCTAssertEqual(typeThroughInputSource(keys, method: .telex, style: "marked"),
                       "thí í the bét password for my business ")
        XCTAssertEqual(typeThroughInputSource(keys, method: .telex, style: "direct"),
                       "this is the best password for my business ")
    }

    func test_equivalence_corpusC_vni() {
        assertEquivalent(Self.corpusC, method: .vni)
    }

    // MARK: - Literal anchors

    func test_anchors_allThreePaths() {
        let anchorsTelex: [(String, String)] = [
            ("xin chaof cacs banj ", "xin chào các bạn "),
            ("tooi ddang hocj tieengs Vieetj ", "tôi đang học tiếng Việt "),
            ("dduwowngf veef quee ", "đường về quê "),
            ("fix bug jira ", "fix bug jira "),
        ]
        for (keys, expected) in anchorsTelex {
            XCTAssertEqual(typeThroughTap(keys, method: .telex), expected, "tap: \(keys)")
            for style in ["marked", "direct"] {
                XCTAssertEqual(typeThroughInputSource(keys, method: .telex, style: style),
                               expected, "style \(style): \(keys)")
            }
        }
        let (keys, expected) = ("tieng61 Viet65 ", "tiếng Việt ")
        XCTAssertEqual(typeThroughTap(keys, method: .vni), expected)
        for style in ["marked", "direct"] {
            XCTAssertEqual(typeThroughInputSource(keys, method: .vni, style: style), expected,
                           "style \(style)")
        }
    }

    // MARK: - Backspace equivalence

    /// For each word of the first sentence of a corpus: type the word, then
    /// press Backspace k times for every k up to the word's length, checking
    /// that the tap screen and the input-source field agree after EVERY
    /// single press, in both styles.
    private func assertBackspaceEquivalence(sentence: String, method: InputMethod,
                                            file: StaticString = #filePath, line: UInt = #line) {
        for word in sentence.split(separator: " ").map(String.init) {
            for k in 1...word.count {
                for style in ["marked", "direct"] {
                    // Each side gets its own engine: the two paths must
                    // replay the same keystrokes independently.
                    let tap = makeEventTap()
                    tap._engine.setInputMethod(method)
                    let sink = RecordingSink()
                    tap.outputSink = sink
                    var field = TextFieldModel()
                    for ch in word {
                        let shifted = ch.isUppercase || Self.shiftedKeyCodes[ch] != nil
                        let code = Self.keyCodes[ch.lowercased().first ?? ch] ?? Self.shiftedKeyCodes[ch] ?? 0
                        tapSend(tap, sink, &field, keyCode: code,
                                flags: shifted ? [.maskShift] : [], unicode: String(ch))
                    }
                    UserDefaults.standard.set(method.rawValue, forKey: DefaultsKey.inputMethod)
                    UserDefaults.standard.set(style, forKey: DefaultsKey.inputSourceStyle)
                    let composer = InputSourceComposer()
                    let client = FakeTextClient()
                    for ch in word {
                        let key = KeyInput(keyCode: inputSourceKeyCode(for: ch),
                                           characters: String(ch),
                                           command: false, control: false, option: false)
                        if !composer.handle(key: key, client: client) {
                            client.nativeInsert(String(ch))
                        }
                    }
                    // Same word typed on both sides - press backspace k times.
                    var bsCount = 0
                    for _ in 0..<k {
                        tapBackspace(tap, sink, &field)
                        composerBackspace(composer, client)
                        bsCount += 1
                        XCTAssertEqual(client.text, field.text,
                                       "\(method) word \"\(word)\" style \(style) after backspace \(bsCount) of \(k)",
                                       file: file, line: line)
                    }
                }
            }
        }
    }

    func test_backspaceEquivalence_corpusA1() {
        assertBackspaceEquivalence(sentence: Self.corpusA[0], method: .telex)
    }

    func test_backspaceEquivalence_corpusC1() {
        assertBackspaceEquivalence(sentence: Self.corpusC[0], method: .vni)
    }
}
