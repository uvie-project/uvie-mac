import Cocoa

/// A keyboard event delivered to the input method, distilled from the
/// `NSEvent` by `UVieInputController` (`event.characters` already carries
/// Shift/Caps Lock case).
struct KeyInput {
    let keyCode: UInt16
    let characters: String?
    let command: Bool
    let control: Bool
    let option: Bool
}

/// The composing-word owner for the input-method process. It renders the
/// current word through the text-input protocol (`setMarkedText`, or direct
/// UTF-16 range replacement) instead of the synthetic backspaces the event
/// tap posts. One instance lives for the whole IM process.
final class InputSourceComposer {
    /// How the composing word is shown to the client.
    enum Style: String {
        /// Marked (underlined) text - the stable default, works everywhere
        /// the text-input protocol is implemented.
        case marked
        /// Replace the word's UTF-16 range in place - no marked text. Falls
        /// back per-app to `.marked` when the client reports a selection
        /// state the replacement cannot trust.
        case direct
    }

    /// Cursor-moving / focus-moving / deletion keys that end the composing
    /// session without committing a boundary char. Mirrors the break-key set
    /// the event tap uses (`EventTap.breakKeyCodes`), minus the keys that
    /// have their own branch here (Backspace, Escape, Return).
    private static let flushKeyCodes: Set<UInt16> = [
        48,   // Tab
        115, 116, 119, 121,       // Home, PageUp, End, PageDown
        123, 124, 125, 126,       // arrows
        114, 117,                 // Help, Forward Delete
    ]

    let engine = EngineBridge()

    private(set) var style: Style = .marked
    private(set) var vietnameseEnabled = true
    private(set) var excludedApps: Set<String> = []
    /// The text currently shown as marked text ("" when none).
    private(set) var markedText = ""
    /// The word currently on screen in `.direct` style and its UTF-16 length.
    private var directWord = ""
    private var directWordLength = 0
    /// The caret position the next `.direct` replacement expects to see -
    /// nil until the first replacement of the word lands.
    private var expectedCaret: Int?
    /// Bundle IDs that failed direct-mode preconditions in this process
    /// lifetime - they fall back to marked text from the next word on.
    private(set) var directUnsupported: Set<String> = []
    /// The input method loaded by the last `reloadSettings` - a change
    /// mid-word must flush the old composition first.
    private var loadedInputMethod: String?
    /// The last client a key was handled for - lets `reloadSettings` flush a
    /// live composition when the input method changes.
    private weak var lastClient: TextInputClient?
    private let macroManager = MacroManager.shared

    init() {
        reloadSettings()
    }

    /// Re-read every setting through `UserDefaults.standard` (the app suite
    /// is added by `InputSourceRuntime`, so the app's values are visible).
    /// If the input method changed mid-word the old composition is flushed
    /// first - re-rendering it under a different method would corrupt it.
    func reloadSettings() {
        let defaults = UserDefaults.standard
        let newMethod = defaults.string(forKey: DefaultsKey.inputMethod) ?? "telex"
        if let loadedInputMethod, loadedInputMethod != newMethod {
            if let lastClient {
                flush(lastClient)
            }
            engine.reset()
            clearCompositionState()
        }
        loadedInputMethod = newMethod
        EngineSettings.apply(to: engine, defaults: defaults)
        vietnameseEnabled = defaults.bool(forKey: DefaultsKey.engineEnabled)
        style = Style(rawValue: defaults.string(forKey: DefaultsKey.inputSourceStyle) ?? Style.marked.rawValue)
            ?? .marked
        excludedApps = getExcludedApps().union(getBypassApps())
    }

    /// The style used for this client: `.direct` only when configured and the
    /// client has not failed direct-mode preconditions before.
    private func effectiveStyle(for client: TextInputClient) -> Style {
        if style == .direct && !directUnsupported.contains(client.clientBundleID) {
            return .direct
        }
        return .marked
    }

    /// The marked text currently on screen - exposed for the controller and
    /// tests (`composingText` in the spec).
    var composingText: String { markedText }

    /// Handle one key. Returns true when the key was consumed by the
    /// composer (the client must not process it further).
    func handle(key: KeyInput, client: TextInputClient) -> Bool {
        lastClient = client

        // Language off, or an app the user excluded: the word on screen is
        // finalized and the key types natively.
        guard vietnameseEnabled, !excludedApps.contains(client.clientBundleID) else {
            flush(client)
            return false
        }

        // Command/Ctrl chords and Option glyphs insert or delete text the
        // engine never sees - finalize and pass through.
        if key.command || key.control || key.option {
            flush(client)
            return false
        }

        switch key.keyCode {
        case 51: // Backspace
            if !engine.isComposing {
                // Nothing of ours to delete: drop any stale state and let
                // the app delete the character natively.
                engine.reset()
                return false
            }
            // Drain invisible raw keys exactly like the event tap does: a
            // raw key that renders nothing produces an empty diff, so keep
            // popping until the screen changes or the word is gone.
            var (bs, out) = engine.backspace()
            if bs == 0 && out.isEmpty && engine.isComposing {
                for _ in 0..<EventTap.maxBackspaceDrain {
                    (bs, out) = engine.backspace()
                    if bs > 0 || !out.isEmpty || !engine.isComposing { break }
                }
            }
            if !engine.isComposing {
                // The drain emptied the word - clear whatever is shown.
                renderShownWord("", style: effectiveStyle(for: client), client: client)
                clearCompositionState()
                return true
            }
            return renderCurrentWord(style: effectiveStyle(for: client), client: client)

        case 53: // Escape
            // EVKey-style restore: replace the rendered word with the literal
            // keystrokes. An empty raw means the word outgrew the engine's
            // raw buffer; a raw equal to the render means nothing to restore.
            if engine.isComposing {
                let out = engine.currentOutput()
                let raw = engine.rawChars()
                if !raw.isEmpty, raw != out {
                    if restoreWord(raw, style: effectiveStyle(for: client), client: client) {
                        engine.reset()
                        clearCompositionState()
                        return true
                    }
                    // Direct-mode preconditions failed - leave the render on
                    // screen and let the Escape through.
                    return false
                }
            }
            flush(client)
            return false

        case 36, 76: // Return, keypad Enter
            commitWord(boundary: "\n", client: client)
            // No post-commit caret tracking in this mode - the engine starts
            // a fresh sentence (mirrors the tap's Enter handling).
            engine.reset()
            clearCompositionState()
            return false

        default:
            break
        }

        // Arrows, Tab, Home/End/PageUp/PageDown, Forward Delete, function
        // keys: the caret moves somewhere the engine cannot track.
        if Self.flushKeyCodes.contains(key.keyCode) {
            flush(client)
            engine.reset()
            clearCompositionState()
            return false
        }

        // A single character event: decide text vs. boundary vs. feedable.
        guard let characters = key.characters, let ch = characters.first, characters.count == 1 else {
            // Function keys and other non-text events end the composition.
            flush(client)
            engine.reset()
            clearCompositionState()
            return false
        }

        // The engine only understands ASCII: a non-ASCII key inserts natively.
        guard let ascii = ch.asciiValue, ascii >= 32 else {
            flush(client)
            engine.reset()
            clearCompositionState()
            return false
        }

        // Whitespace and ASCII punctuation end the word: commit it, note the
        // separator the same way the tap's `afterWordBreak` does, and let the
        // app insert the character natively.
        if ch.isWhitespace || (!ch.isLetter && !ch.isNumber) {
            // Macro expansion on Space - same conditions as `handleSpace`.
            if ch == " ", macroManager.isEnabled() {
                let currentText = engine.committedText() + engine.currentOutput()
                if let expansion = macroManager.findExpansion(for: currentText) {
                    replaceWord(with: expansion, style: effectiveStyle(for: client), client: client)
                    engine.reset()
                    clearCompositionState()
                    return false // the space lands natively after the expansion
                }
            }
            let wasComposing = engine.isComposing
            commitWord(boundary: ch, client: client)
            // No caret tracking here, so the tap's idle-caret branches map to:
            // a separator right after the just-committed word (or inside its
            // tracked trailing gap) is noted; anything else is untracked.
            if wasComposing || engine.trailingGap > 0 {
                engine.noteSeparator(ch)
            } else {
                engine.reset()
            }
            return false
        }

        // ASCII letter or digit: feed it.
        let (bs, out) = engine.feed(char: ch)
        if bs == 0 && out.isEmpty && !engine.isComposing {
            // The engine declined the key - let the app handle it natively
            // (mirrors the tap's "engine didn't process it" guard).
            flush(client)
            return false
        }
        return renderCurrentWord(style: effectiveStyle(for: client), client: client)
    }

    // MARK: - Rendering

    /// Show the engine's current word on the client after a feed/backspace.
    /// Returns false when the direct-mode preconditions fail - the key is
    /// passed through natively and the app falls back to marked text for
    /// the next word.
    private func renderCurrentWord(style: Style, client: TextInputClient) -> Bool {
        renderShownWord(engine.currentOutput(), style: style, client: client)
    }

    /// Show `word` on the client (marked text, or a direct tail replacement).
    /// Returns false on a failed direct-mode precondition.
    @discardableResult
    private func renderShownWord(_ word: String, style: Style, client: TextInputClient) -> Bool {
        switch style {
        case .marked:
            client.setMarkedText(word)
            markedText = word
            return true
        case .direct:
            let old = directWordLength
            let sel = client.selectedRange()
            guard directPreconditionsHold(sel: sel, wordLength: old) else {
                markDirectUnsupported(client)
                return false
            }
            let (tailNew, tailOldLen) = divergentTail(from: directWord, to: word)
            let range: NSRange = tailOldLen == 0
                ? NSRange(location: NSNotFound, length: 0)
                : NSRange(location: sel.location - tailOldLen, length: tailOldLen)
            client.insertText(tailNew, replacementRange: range)
            directWord = word
            directWordLength = word.utf16.count
            expectedCaret = sel.location - tailOldLen + tailNew.utf16.count
            return true
        }
    }

    /// Commit the composing word, if any, and finalize it on screen.
    /// `boundary` is the separator key that ended the word (`nil` = the
    /// plain commit `flush` uses).
    private func commitWord(boundary: Character?, client: TextInputClient) {
        guard engine.isComposing else {
            // Nothing composing: a leftover marked text still gets finalized.
            if !markedText.isEmpty {
                client.insertText(markedText, replacementRange: NSRange(location: NSNotFound, length: 0))
                markedText = ""
            }
            return
        }
        let style = effectiveStyle(for: client)
        let shown = engine.currentOutput()
        let (bs, out) = boundary.map { engine.commitWith(boundary: $0) } ?? engine.commit()
        let shownChars = Array(shown)
        guard bs <= shownChars.count else {
            // A cross-word retro rewrite reaching older committed words.
            switch style {
            case .direct:
                let sel = client.selectedRange()
                guard directPreconditionsHold(sel: sel, wordLength: bs) else {
                    markDirectUnsupported(client)
                    return
                }
                client.insertText(
                    out,
                    replacementRange: NSRange(location: sel.location - bs, length: bs)
                )
                clearDirectState()
            case .marked:
                // The ring can no longer prove the marked text matches the
                // engine's history - commit what is shown and start clean.
                client.insertText(shown, replacementRange: NSRange(location: NSNotFound, length: 0))
                markedText = ""
                engine.reset()
            }
            return
        }
        // `out` is the engine's replacement suffix - the boundary char itself
        // is passed through to the app, never part of it.
        let final = String(shownChars.dropLast(bs)) + out
        switch style {
        case .marked:
            client.insertText(final, replacementRange: NSRange(location: NSNotFound, length: 0))
            markedText = ""
        case .direct:
            let sel = client.selectedRange()
            guard directPreconditionsHold(sel: sel, wordLength: directWordLength) else {
                markDirectUnsupported(client)
                return
            }
            let (tailNew, tailOldLen) = divergentTail(from: directWord, to: final)
            let range: NSRange = tailOldLen == 0
                ? NSRange(location: NSNotFound, length: 0)
                : NSRange(location: sel.location - tailOldLen, length: tailOldLen)
            client.insertText(tailNew, replacementRange: range)
            // The boundary char the app inserts moves the caret - the next
            // word's preconditions start fresh.
            clearDirectState()
        }
    }

    /// Commit whatever is shown without the boundary rules: used when a key
    /// cannot be handled and must pass through.
    func flush(_ client: TextInputClient) {
        commitWord(boundary: nil, client: client)
    }

    /// The client is going away (commitComposition/deactivateServer): commit
    /// the live composition, then drop every engine and render state.
    func abandonWord(_ client: TextInputClient) {
        flush(client)
        engine.reset()
        clearCompositionState()
    }

    // MARK: - Direct-mode helpers

    /// The UTF-16 tail the current replacement touches: the common prefix
    /// stays, `old` contributes `oldTailLength` UTF-16 units of text to
    /// delete and `new` contributes the string to insert.
    private func divergentTail(from old: String, to new: String) -> (tail: String, oldTailLength: Int) {
        let old16 = Array(old.utf16)
        let new16 = Array(new.utf16)
        var prefix = 0
        while prefix < old16.count, prefix < new16.count, old16[prefix] == new16[prefix] {
            prefix += 1
        }
        let tail = String(String(decoding: new16[prefix...], as: UTF16.self))
        return (tail, old16.count - prefix)
    }

    /// The selection state a direct replacement requires: a known caret
    /// (`length == 0`) at or after the tracked word end, matching the
    /// expected caret once one was established.
    private func directPreconditionsHold(sel: NSRange, wordLength: Int) -> Bool {
        sel.location != NSNotFound
            && sel.length == 0
            && sel.location >= wordLength
            && (expectedCaret == nil || sel.location == expectedCaret)
    }

    /// This client cannot do direct replacement reliably (asynchronous
    /// selection or an ignored replacement range). Fall back to marked text
    /// for it - and never replace text on a failed precondition.
    private func markDirectUnsupported(_ client: TextInputClient) {
        directUnsupported.insert(client.clientBundleID)
        engine.reset()
        clearDirectState()
    }

    private func clearDirectState() {
        directWord = ""
        directWordLength = 0
        expectedCaret = nil
    }

    private func clearCompositionState() {
        markedText = ""
        clearDirectState()
    }

    /// Escape restore: replace the whole on-screen word with `text` as final
    /// text. Returns false when direct-mode preconditions fail.
    private func restoreWord(_ text: String, style: Style, client: TextInputClient) -> Bool {
        switch style {
        case .marked:
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            return true
        case .direct:
            let sel = client.selectedRange()
            guard directPreconditionsHold(sel: sel, wordLength: directWordLength),
                  sel.location >= directWordLength else {
                markDirectUnsupported(client)
                return false
            }
            client.insertText(
                text,
                replacementRange: NSRange(location: sel.location - directWordLength, length: directWordLength)
            )
            clearDirectState()
            return true
        }
    }

    /// Replace the whole on-screen word with `text` (macro expansion).
    /// Marked text is replaced through the insert-with-no-range contract;
    /// a direct word is swapped as one range. On a failed direct
    /// precondition nothing is replaced and the app is marked unsupported.
    private func replaceWord(with text: String, style: Style, client: TextInputClient) {
        _ = restoreWord(text, style: style, client: client)
    }
}
