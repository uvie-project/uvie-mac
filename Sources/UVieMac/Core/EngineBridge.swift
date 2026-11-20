import Foundation

// MARK: - C FFI (UvieEngine - diff-based API)

@_silgen_name("uvie_engine_new")
func uvie_engine_new() -> OpaquePointer?

@_silgen_name("uvie_engine_free")
func uvie_engine_free(_ engine: OpaquePointer?)

@_silgen_name("uvie_engine_reset")
func uvie_engine_reset(_ engine: OpaquePointer?)

@_silgen_name("uvie_engine_set_input_method")
func uvie_engine_set_input_method(_ engine: OpaquePointer?, _ method: Int32)

@_silgen_name("uvie_engine_set_modern_orthography")
func uvie_engine_set_modern_orthography(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_set_relaxed_coda")
func uvie_engine_set_relaxed_coda(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_set_quick_telex")
func uvie_engine_set_quick_telex(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_set_quick_start")
func uvie_engine_set_quick_start(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_set_english_override")
func uvie_engine_set_english_override(_ engine: OpaquePointer?, _ enabled: Int32)

@_silgen_name("uvie_engine_feed")
func uvie_engine_feed(_ engine: OpaquePointer?, _ ch: CChar, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_backspace")
func uvie_engine_backspace(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_commit")
func uvie_engine_commit(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_commit_with")
func uvie_engine_commit_with(_ engine: OpaquePointer?, _ boundary: CChar, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_edit_at")
func uvie_engine_edit_at(_ engine: OpaquePointer?, _ caret_back: Int, _ ch: CChar, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int, _ out_fwd_del: UnsafeMutablePointer<Int>?) -> Int

@_silgen_name("uvie_engine_delete_char_at")
func uvie_engine_delete_char_at(_ engine: OpaquePointer?, _ caret_back: Int) -> Int32

@_silgen_name("uvie_engine_note_separator")
func uvie_engine_note_separator(_ engine: OpaquePointer?, _ ch: CChar)

@_silgen_name("uvie_engine_set_context_hint")
func uvie_engine_set_context_hint(_ engine: OpaquePointer?, _ hint: UInt8)

@_silgen_name("uvie_engine_sentence_text")
func uvie_engine_sentence_text(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_remove_separator")
func uvie_engine_remove_separator(_ engine: OpaquePointer?) -> Int32

@_silgen_name("uvie_engine_trailing_gap")
func uvie_engine_trailing_gap(_ engine: OpaquePointer?) -> Int

@_silgen_name("uvie_engine_last_caret_back")
func uvie_engine_last_caret_back(_ engine: OpaquePointer?) -> Int

@_silgen_name("uvie_engine_is_composing")
func uvie_engine_is_composing(_ engine: OpaquePointer?) -> Int32

@_silgen_name("uvie_engine_committed_text")
func uvie_engine_committed_text(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_current_output")
func uvie_engine_current_output(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

@_silgen_name("uvie_engine_raw_chars")
func uvie_engine_raw_chars(_ engine: OpaquePointer?, _ out_buf: UnsafeMutablePointer<CChar>?, _ out_len: Int) -> Int

/// Diff-based Vietnamese input engine wrapper.
/// Returns (backspace_count, new_output) from Rust on each keystroke.
final class EngineBridge {
    private var engine: OpaquePointer?

    /// Output buffer capacity for FFI calls (engine output is at most one
    /// word — 24 raw keystrokes, ≤ 96 bytes even when fully accented).
    private static let bufferCapacity = 128
    /// Reusable output buffer for FFI calls. The engine is only touched from
    /// the event-tap callback (main runloop — see `EventTap.startTap`), so a
    /// single scratch buffer avoids a heap alloc + zeroing on every keystroke.
    /// A static constant is passed as the capacity to avoid an exclusive-access
    /// conflict between `&scratch` and `scratch.count` in the same call.
    private var scratch = [CChar](repeating: 0, count: EngineBridge.bufferCapacity)

    /// Output buffer capacity for `sentenceText()` — a sentence spans up to
    /// 8 committed words, far more than one word's 128 bytes.
    private static let sentenceCapacity = 1024
    /// Reusable buffer for `sentenceText()`, same rationale as `scratch`.
    private var sentenceScratch = [CChar](repeating: 0, count: EngineBridge.sentenceCapacity)

    /// NaturalLanguage recognizer behind the sentence-language hint. One per
    /// engine; asked only at a word commit (see `applyContextHint`).
    private let contextDetector = ContextLanguageDetector()

    /// Cached `contextLanguageDetection` toggle. `commit`/`commitWith` run on
    /// the event-tap callback — a UserDefaults read there is disk-backed and
    /// can stall the tap (same rationale as `Logger.traceEnabledCache`).
    /// Refreshed on `didChangeNotification`; tests pin it directly.
    var contextDetectionEnabled = false

    /// Observer token for the cached toggle above.
    private var contextDefaultsObserver: NSObjectProtocol?

    /// ASCII byte for the FFI's `char` parameters. Boundary/separator chars
    /// are ASCII by construction (space, punctuation, newline); a non-ASCII
    /// char has no byte and maps to 0 ("no char").
    private static func asciiByte(_ char: Character) -> CChar {
        CChar(char.asciiValue ?? 0)
    }

    var isComposing: Bool {
        guard let engine else { return false }
        return uvie_engine_is_composing(engine) != 0
    }

    init() {
        engine = uvie_engine_new()
        contextDetectionEnabled = Self.readContextDetectionEnabled()
        // Registered after `engine` is set — the closure captures `self`,
        // which is only valid once init completes. The Settings toggle writes
        // via @AppStorage in-process, so the notification always fires.
        contextDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.contextDetectionEnabled = Self.readContextDetectionEnabled()
        }
    }

    deinit {
        if let contextDefaultsObserver {
            NotificationCenter.default.removeObserver(contextDefaultsObserver)
        }
        if let engine {
            uvie_engine_free(engine)
        }
    }

    /// Read the `contextLanguageDetection` toggle off the hot path. A missing
    /// key counts as enabled: the app registers it as a factory default, and
    /// an external `defaults delete` must not silently drop the feature.
    private static func readContextDetectionEnabled() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: DefaultsKey.contextLanguageDetection) == nil
            || defaults.bool(forKey: DefaultsKey.contextLanguageDetection)
    }

    // MARK: - Configuration

    func setInputMethod(_ method: InputMethod) {
        guard let engine else { return }
        let code: Int32 = switch method {
        case .telex: 0
        case .vni: 1
        case .simpleTelex: 2
        }
        uvie_engine_set_input_method(engine, code)
    }

    func setModernOrthography(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_modern_orthography(engine, enabled ? 1 : 0)
    }

    func setRelaxedCoda(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_relaxed_coda(engine, enabled ? 1 : 0)
    }

    func setQuickTelex(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_quick_telex(engine, enabled ? 1 : 0)
    }

    func setQuickStart(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_quick_start(engine, enabled ? 1 : 0)
    }

    /// English-dictionary override: when a typed word matches a known English
    /// word, restore the raw English instead of the Vietnamese transform.
    func setEnglishOverride(_ enabled: Bool) {
        guard let engine else { return }
        uvie_engine_set_english_override(engine, enabled ? 1 : 0)
    }

    /// Sentence-language hint the engine applies at the NEXT commit: `.auto`
    /// (its own rules), `.vietnamese` or `.english`. The engine resets it to
    /// auto at a sentence boundary and on every reset, so the host re-sends
    /// the verdict before each commit (see `applyContextHint`).
    func setContextHint(_ hint: ContextHint) {
        guard let engine else { return }
        uvie_engine_set_context_hint(engine, hint.rawValue)
    }

    // MARK: - Keystroke handling

    /// Feed a single character. Returns (backspaces, new_output).
    /// The Rust engine tracks uppercase via the raw key byte, so we must pass
    /// the original ASCII byte (e.g., 'A' stays 'A') instead of lowercasing it.
    func feed(char: Character) -> (Int, String) {
        guard let engine else { return (0, "") }
        // Only ASCII keys are feedable; non-ASCII passes 0 which the engine ignores.
        let byte = CChar(char.asciiValue ?? 0)
        let bs = uvie_engine_feed(engine, byte, &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    /// Backspace. Returns (backspaces, new_output).
    func backspace() -> (Int, String) {
        guard let engine else { return (0, "") }
        let bs = uvie_engine_backspace(engine, &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    func commit() -> (Int, String) {
        guard let engine else { return (0, "") }
        applyContextHint()
        let bs = uvie_engine_commit(engine, &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    /// Commit the composing word at the separator key `boundary` that ended
    /// it (Space → ' ', punctuation → the char, Enter → '\n', `"\0"` when the
    /// host has no char). The boundary char decides the code-identifier
    /// rule: a word a code char terminates (`raw_chars`, `feed_diff`,
    /// `UVIE_RS_DIR`) shows its literal keystrokes.
    func commitWith(boundary: Character) -> (Int, String) {
        guard let engine else { return (0, "") }
        applyContextHint()
        let bs = uvie_engine_commit_with(engine, Self.asciiByte(boundary), &scratch, Self.bufferCapacity)
        return (bs, String(cString: scratch))
    }

    /// Re-enter a committed word with `char` appended to its raw keystrokes
    /// (LabanKey-style post-commit editing). `caretBack` is the caret
    /// distance (screen chars) back to the end of the newest committed word;
    /// it must land exactly on a word-end boundary (0 = the newest word,
    /// + rendered_len + gap per older word) or strictly inside a word
    /// (mid-word edit). Returns (backspaces, forwardDeletes, new_output)
    /// when handled, nil when there is no match (the caller then feeds the
    /// key normally). `backspaces` deletes the rendered chars left of the
    /// caret; `forwardDeletes` is 0 for word-end edits and the old word's
    /// tail length for mid-word edits — the host must forward-delete that
    /// many chars before inserting `new_output` (the whole re-rendered
    /// word). The edited entry is updated in place and the engine stays
    /// idle, so the caller's new caret offset is `lastCaretBack`.
    func editAt(caretBack: Int, char: Character) -> (backspaces: Int, forwardDeletes: Int, suffix: String)? {
        guard let engine, caretBack >= 0 else { return nil }
        // Only ASCII keys are feedable; non-ASCII passes 0 which the engine
        // treats as "not handled".
        guard let ascii = char.asciiValue else { return nil }
        let byte = CChar(ascii)
        var fwdDel = 0
        let r = uvie_engine_edit_at(engine, caretBack, byte, &scratch, Self.bufferCapacity, &fwdDel)
        guard r > 0 else { return nil }
        return (r - 1, fwdDel, String(cString: scratch))
    }

    func reset() {
        guard let engine else { return }
        uvie_engine_reset(engine)
    }

    // MARK: - Committed-word geometry

    /// Backspace with the caret on a committed word's end: the app deletes one
    /// visible char natively (the key passes through — no synthetic delete +
    /// retype racing the key repeat) and the engine only shrinks that word's
    /// tracked text so it stays editable. `caretBack` must match a word-end
    /// boundary; mid-word carets and an empty history decline. Returns false
    /// when the deletion was not tracked — the caller then drops its caret
    /// history. The engine stays idle, so the caller's new caret offset is
    /// `lastCaretBack`.
    func deleteCharAt(caretBack: Int) -> Bool {
        guard let engine, caretBack >= 0 else { return false }
        return uvie_engine_delete_char_at(engine, caretBack) != 0
    }

    /// A separator char (space / punctuation / Enter) was typed right after
    /// the newest committed word. The char itself matters: a code char glued
    /// to the text before it (`_` in `foo_bar`, `.` in `a.b`) marks the next
    /// word as a code identifier. No-op while nothing is committed.
    func noteSeparator(_ separator: Character) {
        guard let engine else { return }
        uvie_engine_note_separator(engine, Self.asciiByte(separator))
    }

    // MARK: - Sentence context

    /// The current sentence so far — its committed words with their
    /// separators, oldest first — as UTF-8. The composing word is not
    /// included. A sentence longer than the engine's committed-word ring keeps
    /// only its newest words.
    func sentenceText() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_sentence_text(engine, &sentenceScratch, Self.sentenceCapacity)
        return String(cString: sentenceScratch)
    }

    /// Ask NaturalLanguage which language the sentence is in and hand the
    /// verdict to the engine right before a commit — the one place a word's
    /// final rendering is decided (CGEvent path and `AXTextInjector` both
    /// commit through here). Never per keystroke: the recognizer costs ~1 ms.
    private func applyContextHint() {
        guard contextDetectionEnabled else { return }
        let hint = contextDetector.hint(for: sentenceText(), pendingRaw: "")
        setContextHint(hint)
        if Logger.shared.keystrokeTraceEnabled {
            Logger.shared.keystroke(String(
                format: "ctx hint=%@ vi=%.2f en=%.2f text=%@",
                hint.traceName,
                contextDetector.lastVietnameseProbability,
                contextDetector.lastEnglishProbability,
                contextDetector.lastText
            ))
        }
    }

    /// A separator char right after the newest committed word was deleted.
    /// Returns false when there is no separator left to account for.
    func removeSeparator() -> Bool {
        guard let engine else { return false }
        return uvie_engine_remove_separator(engine) != 0
    }

    /// Separator chars currently on screen right after the newest committed
    /// word (the caret offset 0 sits just left of them).
    var trailingGap: Int {
        guard let engine else { return 0 }
        return uvie_engine_trailing_gap(engine)
    }

    /// Caret offset the host must adopt after the last successful edit or
    /// committed-word backspace.
    var lastCaretBack: Int {
        guard let engine else { return 0 }
        return uvie_engine_last_caret_back(engine)
    }

    func committedText() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_committed_text(engine, &scratch, Self.bufferCapacity)
        return String(cString: scratch)
    }

    func currentOutput() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_current_output(engine, &scratch, Self.bufferCapacity)
        return String(cString: scratch)
    }

    /// Raw keystrokes of the whole current word (across V-C-V splits, tone
    /// cancels and dictionary commits). Empty when the word outgrew the
    /// engine's raw buffer — the caller must not restore it then.
    func rawChars() -> String {
        guard let engine else { return "" }
        _ = uvie_engine_raw_chars(engine, &scratch, Self.bufferCapacity)
        return String(cString: scratch)
    }
}

enum InputMethod: String, CaseIterable, Identifiable {
    case telex
    case vni
    case simpleTelex
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex: return "Simple Telex"
        }
    }
}
