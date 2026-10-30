import Cocoa
import ApplicationServices

/// Injects text via Accessibility API (AXUIElement) instead of CGEventTap.
/// Used for apps where synthetic key events don't work (Spotlight, some secure fields).
///
/// Shares the same `EngineBridge` instance as `EventTap` so that configuration
/// (input method, quick modes, modern orthography) is always consistent.
final class AXTextInjector {
    private let engine: EngineBridge
    private let macroManager = MacroManager.shared

    init(engine: EngineBridge) {
        self.engine = engine
    }

    // MARK: - Keystroke handling

    /// Last value we wrote into `lastWrittenElement`, and that element.
    ///
    /// The field read can lag our own write: Spotlight updates its search
    /// field asynchronously, so `kAXValueAttribute` may still return the text
    /// from one keystroke ago. Applying a diff to that stale text leaves the
    /// previous character behind and the next diff appends on top of it.
    private var lastWrittenText: String?
    private var lastWrittenElement: AXUIElement?

    /// Feed a character. Returns true if AX injection succeeded.
    func feed(char: Character) -> Bool {
        guard let element = getFocusedTextElement() else {
            return false
        }

        let previous = engine.currentOutput()
        let (bs, out) = engine.feed(char: char)
        // Check if engine processed the character (even if output is empty for literal chars)
        // If engine is composing or produced output, we should inject
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Engine didn't process and we're not composing - let OS handle it
            return false
        }

        if inject(bs: bs, out: out, element: element, previous: previous) {
            return true
        }
        // AX injection failed but engine already consumed the char.
        // Only reset if engine state diverged from screen (bs > 0 or
        // output differs from raw char). If output == char and bs == 0,
        // engine just appended a literal — screen will get it from the
        // passed-through OS event, so no desync.
        if bs > 0 || out != String(char) {
            engine.reset()
        }
        return false
    }

    /// Backspace. Returns true if AX injection succeeded.
    func backspace() -> Bool {
        guard let element = getFocusedTextElement() else {
            return false
        }

        let previous = engine.currentOutput()
        var (bs, out) = engine.backspace()
        // Same invisible-raw-key drain as the CGEvent path: a word can end in
        // a key that renders nothing ("aow" → "ao"), and the engine then
        // reports an empty diff. Consuming the Backspace without deleting
        // anything looks like a dead key.
        if bs == 0 && out.isEmpty && engine.isComposing {
            for _ in 0..<EventTap.maxBackspaceDrain {
                (bs, out) = engine.backspace()
                if bs > 0 || !out.isEmpty || !engine.isComposing { break }
            }
        }
        // Inject if: we have backspaces, we have output, or engine is still composing
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Nothing to do - let OS handle backspace
            return false
        }

        if inject(bs: bs, out: out, element: element, previous: previous) {
            return true
        }
        // AX injection failed but engine already processed backspace.
        // Reset to prevent desync — backspace always changes engine state.
        engine.reset()
        return false
    }

    /// Try to inject (bs, out) via AX. Returns true if successful.
    /// Kept for callers that already advanced the engine.
    func tryInject(bs: Int, out: String) -> Bool {
        guard let element = getFocusedTextElement() else { return false }
        return inject(bs: bs, out: out, element: element, previous: engine.currentOutput())
    }

    /// How the new field value is based.
    enum InjectionBase: Equatable {
        /// The field text is in sync with the engine model.
        case field(String)
        /// The read is stale (our own last write already landed), so apply the
        /// diff to our last written value instead.
        case lastWrite(String)
        /// The field no longer matches the engine model; the composition must
        /// be dropped rather than diffed into someone else's text.
        case diverged
    }

    /// Decide the base for the next write. Pure + internal so tests can pin
    /// the stale-read and divergence rules without AX IPC.
    ///
    /// `previous` is the engine's composing output BEFORE the operation: a
    /// field that does not end with it has either not caught up with our last
    /// write (stale read) or was changed by someone else.
    static func resolveBase(
        current: String,
        previous: String,
        lastWritten: String?,
        sameElement: Bool
    ) -> InjectionBase {
        if previous.isEmpty || current.hasSuffix(previous) { return .field(current) }
        if let lastWritten, sameElement, lastWritten.hasSuffix(previous),
           current.utf16.count <= lastWritten.utf16.count {
            return .lastWrite(lastWritten)
        }
        return .diverged
    }

    /// Apply `(bs, out)` to the focused field's text and write it back.
    /// `previous` is the engine's composing output BEFORE the operation.
    private func inject(bs: Int, out: String, element: AXUIElement, previous: String) -> Bool {
        guard let current = getTextValue(element) else {
            return false
        }

        var base = current
        switch Self.resolveBase(
            current: current,
            previous: previous,
            lastWritten: lastWrittenText,
            sameElement: lastWrittenElement.map { CFEqual($0, element) } ?? false
        ) {
        case .field(let text):
            base = text
        case .lastWrite(let text):
            // The read is one write behind; our own value is the truth.
            base = text
            Logger.shared.debug("AXTextInjector: stale field read, injecting from the last write")
        case .diverged:
            // A passed-through key, a paste, or Spotlight rewriting the value.
            // Diffing into that text duplicates or deletes the wrong chars.
            Logger.shared.warn("AXTextInjector: field diverged from the engine model, dropping the composition")
            engine.reset()
            lastWrittenText = nil
            lastWrittenElement = nil
            return false
        }

        // Spotlight reopens with the previous query selected, so typing
        // replaces it natively. Our whole-value write must do the same: at the
        // start of a word, a fully selected field is replaced instead of
        // appended to, otherwise the stale query stays in front of the new
        // word and every later diff keeps it ("ơ" left over + "ows" rendered
        // "ơớ"). Only checked while the engine has no composing word - once it
        // does, the field belongs to us and the diff must apply to it.
        if bs == 0, !current.isEmpty, previous.isEmpty,
           isEntireTextSelected(element, length: current.utf16.count) {
            base = ""
        }

        let newText = Self.composeText(current: base, bs: bs, out: out)

        // Trust the AXError instead of a read-back verification. The read-back
        // raced with Spotlight's live search: a write that had already landed
        // followed by a stale read returned false → the caller let the real
        // keystroke pass through natively ON TOP of the written text → double
        // input ("viej" became "viejj" → fast-typing "việt" became "vieệt").
        // A genuinely failed write is already reported by the error code.
        guard setTextValue(element, text: newText) == .success else {
            return false
        }
        // AX ranges are measured in UTF-16 code units, not Swift Character
        // (grapheme) count. Using .count for decomposed Vietnamese or emoji
        // places the cursor before the real end. Use utf16.count instead.
        setCursorToEnd(element, length: newText.utf16.count)
        lastWrittenText = newText
        lastWrittenElement = element
        if Logger.shared.keystrokeTraceEnabled {
            Logger.shared.keystroke("axInject prev='\(previous)' field='\(current)' bs=\(bs) out='\(out)' -> '\(newText)'")
        }
        return true
    }

    /// True when the field's selection covers the whole value, i.e. typing
    /// natively would replace it.
    private func isEntireTextSelected(_ element: AXUIElement, length: Int) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return false
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return false }
        return range.location == 0 && range.length == length
    }

    /// Pure transform shared by every injection path: drop `bs` trailing
    /// grapheme clusters from the current field text and append the engine
    /// output. Internal + static so tests can pin the semantics — `dropLast`
    /// operates on grapheme clusters (a decomposed Vietnamese vowel with its
    /// tone mark is ONE cluster), while cursor placement must use
    /// `utf16.count` (AX ranges are UTF-16 based).
    static func composeText(current: String, bs: Int, out: String) -> String {
        var newText = String(current.dropLast(bs))
        newText += out
        return newText
    }

    /// Commit on word boundary. Returns true if a macro expansion was
    /// performed (caller should consume the triggering key to avoid a
    /// trailing space/return after the expanded text).
    @discardableResult
    func commit() -> Bool {
        // Check for macro expansion first
        if macroManager.isEnabled() {
            // Include V-C-V auto-committed prefix + composing for macro matching.
            let currentText = engine.committedText() + engine.currentOutput()
            if let expansion = macroManager.findExpansion(for: currentText) {
                guard let element = getFocusedTextElement() else { return false }
                guard let current = getTextValue(element) else { return false }

                // Backspace the abbreviation (single dropLast — see tryInject)
                let abbreviationLength = currentText.count
                var newText = String(current.dropLast(abbreviationLength))
                newText += expansion

                _ = setTextValue(element, text: newText)
                setCursorToEnd(element, length: newText.utf16.count)
                lastWrittenText = newText
                lastWrittenElement = element
                engine.reset()
                return true
            }
        }
        _ = engine.commit()
        return false
    }

    func reset() {
        engine.reset()
        // Focus moved (app switch, excluded tap): the cached field value
        // belongs to another field and must not be used as an injection base.
        lastWrittenText = nil
        lastWrittenElement = nil
    }

    // MARK: - AX Helpers

    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        // Bound the AX round-trips on the event-tap callback: a hung target
        // app would otherwise stall the tap past the system timeout.
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let focused = focusedElement else { return nil }
        // In Swift, CFTypeRef from Copy functions is ARC-managed — no
        // manual CFRelease needed. The bridge to AXUIElement transfers
        // ownership to ARC automatically.
        // `AXUIElement` casts are not runtime-checked (`as?` is treated as
        // always succeeding by the compiler), so verify the actual CF type
        // first. A broken AX hierarchy can hand back e.g. a CFString for
        // kAXFocusedUIElementAttribute, and the forced cast would then trap
        // on the event-tap callback and kill the app. Same guard as
        // `EventTap.computeIsFocusedFieldWebContent`.
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }

    private func getTextValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func setTextValue(_ element: AXUIElement, text: String) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
    }

    private func setCursorToEnd(_ element: AXUIElement, length: Int) {
        var range = CFRange(location: length, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
    }
}
