import Cocoa

// MARK: - EventTap - Synthetic Output

/// The synthetic-event injection surface of `EventTap`. Production posts real
/// CGEvents; tests substitute a recording sink so `handle()` can be driven
/// with simulated keystrokes without touching the host session.
protocol SyntheticOutputSink: AnyObject {
    func applyCompoundBackspaces(bs: Int, out: String)
    func applyCompoundForwardDeletes(_ count: Int)
    func applyBackspaces(_ count: Int)
    func applyForwardDeletes(_ count: Int)
    func applySelectionBackspaces(_ count: Int)
    func applySelectionForwardDeletes(_ count: Int)
    func sendEmptyCharacter()
    func postText(_ string: String)
    func postKey(keyCode: Int64, flags: CGEventFlags)
}

extension EventTap: SyntheticOutputSink {}

extension EventTap {
    // MARK: - In-flight bookkeeping

    /// Record `count` synthetic keyDown posts. Called by every helper that
    /// posts an event the app acts on, so `handle` can tell whether a rewrite
    /// is still in flight when the next real key arrives. Warm-up phantoms
    /// and `releaseSyntheticModifiers` are keyUps and are NOT counted (only
    /// keyDowns come back through the tap as text/deletion events).
    func noteSyntheticPosts(_ count: Int) {
        guard count > 0 else { return }
        pendingSynthetic += count
        lastSyntheticPostTime = CFAbsoluteTimeGetCurrent()
    }

    /// True while a synthetic post may still be in flight. Clears the count
    /// when the newest post is older than `pendingSyntheticTimeout`, so a lost
    /// event (or a tap that was disabled mid-flight) can never keep native
    /// keys on the re-post path.
    func syntheticEventsInFlight() -> Bool {
        if pendingSynthetic > 0,
           CFAbsoluteTimeGetCurrent() - lastSyntheticPostTime > Self.pendingSyntheticTimeout {
            pendingSynthetic = 0
        }
        return pendingSynthetic > 0
    }

    /// Send backspaces for compound apps (Safari, Notes, Chrome, Comet, Atlas, etc.).
    ///
    /// Strategy:
    /// - For non-Chromium compound apps (Safari, Notes, TextEdit, Mail, iWork):
    ///   When replacing text (out is non-empty), use Shift+Left selection +
    ///   overwrite. This is atomic — the selection is replaced by the
    ///   subsequent postText in a single operation, eliminating the
    ///   "delete then insert" flicker that plain backspaces cause.
    ///   The empty-char sentinel is NOT needed with selection-based delete
    ///   because selecting text doesn't trigger autocomplete dropdowns.
    /// - For Chromium browsers (Chrome, Brave, Edge, Arc, BrowserOS, etc.):
    ///   The right strategy depends on whether the focused field is native or
    ///   web content. The omnibox/address bar is a native `AXTextField` where
    ///   Shift+Left selection works — use it (avoids the U+202F sentinel
    ///   corrupting the URL/search text). Web contenteditable fields (Google
    ///   Docs) don't establish a selection from synthetic Shift+Left, so
    ///   `postText` would append instead of replacing — use plain backspaces
    ///   + sentinel there. The distinction is made via `isFocusedFieldWebContent()`
    ///   which walks the AX parent chain for an `AXWebArea` ancestor.
    /// - For pure deletions (out is empty, any compound app), use plain
    ///   backspaces with the empty-char sentinel when bs > 1.
    func applyCompoundBackspaces(bs: Int, out: String) {
        if !out.isEmpty && (!isChromium || !isFocusedFieldWebContent()) {
            // Replace in a non-web-content field: selection-based delete is
            // atomic (no flicker). Shift+Left selects the text without
            // deleting it, then postText replaces the selection in one
            // operation. Covers non-Chromium compound apps and Chromium
            // native fields (omnibox/address bar) — the latter avoids the
            // U+202F sentinel corrupting the URL/search text, restoring the
            // pre-1.5.0 behavior that the caf1184 commit regressed.
            applySelectionBackspaces(bs)
        } else {
            // Chromium web contenteditable (Google Docs) replace OR pure
            // deletion (any compound app): plain backspaces + sentinel.
            let needsEmptyChar = bs > 1
            if needsEmptyChar {
                sendEmptyCharacter()
            }
            let adjustedBs = bs + (needsEmptyChar ? 1 : 0)
            applyBackspaces(adjustedBs)
        }
    }

    /// Forward-delete for compound apps — the mid-word-edit tail removal
    /// counterpart to `applyCompoundBackspaces`.
    ///
    /// Chromium web contenteditable fields don't establish a selection from
    /// synthetic Shift+Right (same limitation as Shift+Left documented on
    /// `applyCompoundBackspaces`), so they take plain forward-deletes.
    /// Everywhere else the tail is selected with Shift+Right and removed
    /// with a single Forward Delete — one real delete event on a selection
    /// doesn't hit the duplicated-backspace bug that motivated the
    /// selection-based strategy.
    func applyCompoundForwardDeletes(_ count: Int) {
        if !isChromium || !isFocusedFieldWebContent() {
            applySelectionForwardDeletes(count)
            applyForwardDeletes(1)
        } else {
            applyForwardDeletes(count)
        }
    }

    /// Forward-deletes (kVK_ForwardDelete). Deletes `count` chars right of
    /// the caret — used by mid-word edits to remove the old word's tail
    /// before the re-rendered word is posted.
    ///
    /// Only posts keyDown — same rationale as `applyBackspaces`.
    func applyForwardDeletes(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(count)
        noteSyntheticPosts(count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 117, keyDown: true)
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cgSessionEventTap)
        }
    }

    /// Shift+Right Arrow selection of `count` chars right of the caret —
    /// the mid-word-edit tail. The caller removes the selection with a
    /// forward-delete (see `applyCompoundForwardDeletes`).
    ///
    /// Only posts keyDown — same rationale as `applySelectionBackspaces`.
    func applySelectionForwardDeletes(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(count)
        noteSyntheticPosts(count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 124, keyDown: true)
            down?.flags = .maskShift
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cgSessionEventTap)
        }
        releaseSyntheticModifiers()
    }

    /// Warm up the synthetic keycode path right after the tap is created.
    ///
    /// The FIRST keycode event posted by a freshly-rebuilt binary can be
    /// transiently dropped while the system re-validates the posting process
    /// (observed: the first synthetic backspace after launching a new build
    /// never reached the focused app — fast-typing "việt" became "vieệt";
    /// every later launch without a rebuild was unaffected. Unicode-string
    /// events via `postText` were never affected — only keycode posts).
    ///
    /// The warm-up posts sacrificial events that are harmless in every
    /// failure mode:
    /// - keyUp events never insert text, so a phantom keyUp is a no-op even
    ///   if delivered late or out of order.
    /// - a bare Cmd keyDown+keyUp pair with no other key in between produces
    ///   no character and leaves no modifier state behind.
    /// All events are tagged with `syntheticTag` so this tap skips them, and
    /// none of them are counted as in-flight posts (`noteSyntheticPosts`):
    /// they are phantoms, not text or deletion events.
    func warmUpSyntheticKeycodePath() {
        guard let eventSource else { return }
        func post(_ event: CGEvent?, flags: CGEventFlags) {
            guard let event else { return }
            event.flags = flags
            event.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
        // Absorb a keyDown-targeted drop: bare Cmd tap.
        post(CGEvent(keyboardEventSource: eventSource, virtualKey: 54, keyDown: true), flags: [])
        post(CGEvent(keyboardEventSource: eventSource, virtualKey: 54, keyDown: false), flags: [])
        // Absorb an any-keycode-event drop: phantom keyUps.
        post(CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: false), flags: [])
        post(CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: false), flags: .maskShift)
        // The session's combined modifier state follows the LAST posted event:
        // ending on a Shift-tagged event left Shift latched for every process
        // until the next real key press. Finish with an unmodified phantom.
        post(CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: false), flags: [])
    }

    /// Standard backspaces.
    ///
    /// Only posts keyDown — the synthetic keyUp is unnecessary for deletion
    /// and doubles the event count, amplifying the backspace-then-insert
    /// flicker on every diff replace. Apps process the delete on keyDown.
    ///
    /// Posts to `.cgSessionEventTap`, NOT `.cghidEventTap`: keycode-only
    /// events posted at the HID level traverse the HID translation path,
    /// where the first post after a binary rebuild can be transiently
    /// dropped (Input Monitoring re-evaluation) — the swallowed backspace
    /// corrupts the first diff replace after launch ("việt" → "vieệt").
    /// Session-level posting skips the HID path entirely. ALL synthetic
    /// events must post to the SAME tap location so backspace → text
    /// ordering is guaranteed (FIFO within one entry point).
    func applyBackspaces(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(count)
        noteSyntheticPosts(count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true)
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cgSessionEventTap)
        }
    }

    /// The session's combined modifier state follows the LAST posted event:
    /// ending a Shift+arrow selection on a Shift-tagged event left Shift
    /// latched for every process until the next real key press. Post an
    /// unmodified phantom keyUp to clear it.
    ///
    /// A keyUp, so it is not counted as an in-flight post.
    func releaseSyntheticModifiers() {
        guard let eventSource else { return }
        let release = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: false)
        release?.flags = []
        release?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        release?.post(tap: .cgSessionEventTap)
    }

    /// Shift+Left Arrow selection used for apps where synthetic backspace causes
    /// duplicate characters. The caller must post the replacement text afterward.
    ///
    /// Only posts keyDown — same rationale as applyBackspaces.
    func applySelectionBackspaces(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(count)
        noteSyntheticPosts(count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: true)
            down?.flags = .maskShift
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cgSessionEventTap)
        }
        releaseSyntheticModifiers()
    }

    /// Send U+202F (Narrow No-Break Space) to invalidate autocomplete dropdown.
    ///
    /// Only posts keyDown — same rationale as applyBackspaces.
    func sendEmptyCharacter() {
        guard let eventSource else { return }
        perfNoteEvent(1)
        noteSyntheticPosts(1)
        let emptyChar: UniChar = 0x202F
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [emptyChar])
        down?.post(tap: .cgSessionEventTap)
    }

    func postText(_ string: String) {
        guard let eventSource, !string.isEmpty else { return }
        perfNoteEvent(1)
        let utf16 = Array(string.utf16)
        guard !utf16.isEmpty else { return }
        noteSyntheticPosts(1)
        // Only post keyDown — apps render text on keyDown; the synthetic keyUp
        // is unnecessary for text input and doubles the event count, amplifying
        // the backspace-then-insert flicker on every diff replace.
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cgSessionEventTap)
    }

    /// Re-post a key the tap consumed, keeping its keycode and modifier flags
    /// (Shift+Enter must stay Shift+Enter). Used when a commit rewrite
    /// consumes the boundary key: the synthetic keyDown is posted AFTER the
    /// plan, and every post shares the same tap entry so the order is FIFO.
    /// Only posts keyDown — the app's real keyUp follows the consumed one and
    /// is passed through by the tap, so the key cycle still balances.
    func postKey(keyCode: Int64, flags: CGEventFlags) {
        guard let eventSource else { return }
        perfNoteEvent(1)
        noteSyntheticPosts(1)
        let down = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(clamping: keyCode),
            keyDown: true
        )
        down?.flags = flags
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.post(tap: .cgSessionEventTap)
    }
}
