import Cocoa
import XCTest
@testable import UVieMac

// MARK: - Recording synthetic-output sink

/// Records injection calls instead of posting real CGEvents, so `handle()`
/// can be driven with simulated keystrokes without touching the host session.
final class RecordingSink: SyntheticOutputSink {
    struct Call: Equatable {
        let method: String
        let arg: String

        static func backspaces(_ n: Int) -> Call { Call(method: "backspaces", arg: "\(n)") }
        static func forwardDeletes(_ n: Int) -> Call { Call(method: "forwardDeletes", arg: "\(n)") }
        static func text(_ s: String) -> Call { Call(method: "text", arg: s) }
        static func compound(_ bs: Int, _ out: String) -> Call { Call(method: "compoundBackspaces", arg: "\(bs)|\(out)") }
        static func compoundForward(_ n: Int) -> Call { Call(method: "compoundForwardDeletes", arg: "\(n)") }
        static func selection(_ n: Int) -> Call { Call(method: "selectionBackspaces", arg: "\(n)") }
        static func selectionForward(_ n: Int) -> Call { Call(method: "selectionForwardDeletes", arg: "\(n)") }
        static func emptyChar() -> Call { Call(method: "emptyChar", arg: "") }
        static func key(_ code: Int64, _ flags: CGEventFlags = []) -> Call {
            Call(method: "key", arg: "\(code)|\(flags.rawValue)")
        }
    }

    private(set) var calls: [Call] = []

    /// A recorded post the app has not applied yet. `posts` is how many
    /// synthetic keyDown events the call posted - the unit `pendingSynthetic`
    /// counts.
    struct InFlightPost {
        let call: Call
        let posts: Int
    }

    /// Synthetic posts that are still "in the air" (see `modelsInFlight`).
    private(set) var inFlight: [InFlightPost] = []

    /// When true, a recorded post is not delivered to the app immediately: it
    /// stays in `inFlight` and raises `tap.pendingSynthetic`, modelling the
    /// real event stream where a synthetic event reaches the app only after
    /// the system dispatches it. Off by default, so the existing tests keep
    /// the "delivered in order, immediately" model.
    var modelsInFlight = false

    /// The tap whose in-flight counter the recorded posts feed.
    weak var tap: EventTap?

    /// Clears the recorded calls. In-flight posts are NOT delivered: they are
    /// still in the air and must be pumped.
    func reset() {
        calls.removeAll()
    }

    /// Records a call and, when in-flight delivery is modelled, queues the
    /// posts it made. `posts` is approximate for the compound strategies
    /// (their internal selection/sentinel events are not modelled).
    private func record(_ call: Call, posts: Int) {
        calls.append(call)
        guard modelsInFlight, posts > 0 else { return }
        inFlight.append(InFlightPost(call: call, posts: posts))
        tap?.noteSyntheticPosts(posts)
    }

    /// Delivers every queued post to the app, oldest first: `apply` performs
    /// the screen edit the app would make, then the tap sees the synthetic
    /// event come back through it (dropping the in-flight count), exactly as
    /// in the real event stream.
    func deliverAll(_ apply: (Call) -> Void) {
        while !inFlight.isEmpty {
            let entry = inFlight.removeFirst()
            apply(entry.call)
            guard let tap else { continue }
            for _ in 0..<entry.posts {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
                event.setIntegerValueField(.eventSourceStateID, value: tap.syntheticTag)
                send(tap, .keyDown, event)?.release()
            }
        }
    }

    func applyCompoundBackspaces(bs: Int, out: String) {
        record(.compound(bs, out), posts: bs + (out.isEmpty ? 0 : 1))
    }

    func applyBackspaces(_ count: Int) {
        record(.backspaces(count), posts: count)
    }

    func applyForwardDeletes(_ count: Int) {
        record(.forwardDeletes(count), posts: count)
    }

    func applyCompoundForwardDeletes(_ count: Int) {
        record(.compoundForward(count), posts: count + 1)
    }

    func applySelectionBackspaces(_ count: Int) {
        record(.selection(count), posts: count)
    }

    func applySelectionForwardDeletes(_ count: Int) {
        record(.selectionForward(count), posts: count)
    }

    func sendEmptyCharacter() {
        record(.emptyChar(), posts: 1)
    }

    func postText(_ string: String) {
        record(.text(string), posts: string.isEmpty ? 0 : 1)
    }

    func postKey(keyCode: Int64, flags: CGEventFlags) {
        record(.key(keyCode, flags), posts: 1)
    }
}

// MARK: - Text field model

/// Minimal single-line text field for the in-flight delivery tests: a
/// character buffer with a caret that applies the recorded injection calls
/// and the native edits a passed-through key performs, the same math a real
/// field does.
struct TextFieldModel {
    private(set) var chars: [Character] = []
    private(set) var caret = 0

    var text: String { String(chars) }

    mutating func insert(_ ch: Character) {
        chars.insert(ch, at: caret)
        caret += 1
    }

    mutating func backspace(_ count: Int) {
        for _ in 0..<count where caret > 0 {
            caret -= 1
            chars.remove(at: caret)
        }
    }

    mutating func forwardDelete(_ count: Int) {
        for _ in 0..<count where caret < chars.count {
            chars.remove(at: caret)
        }
    }

    /// Applies an injection call the way the app receives it.
    mutating func apply(_ call: RecordingSink.Call) {
        switch call.method {
        case "backspaces", "selectionBackspaces":
            backspace(Int(call.arg) ?? 0)
        case "compoundBackspaces":
            let parts = call.arg.split(separator: "|", maxSplits: 1).map(String.init)
            backspace(Int(parts[0]) ?? 0)
            if parts.count > 1 { for ch in parts[1] { insert(ch) } }
        case "forwardDeletes", "compoundForwardDeletes", "selectionForwardDeletes":
            forwardDelete(Int(call.arg) ?? 0)
        case "text":
            for ch in call.arg { insert(ch) }
        case "key":
            applyKey(call)
        default:
            break
        }
    }

    /// A re-posted key behaves like the real one: Backspace/Forward Delete
    /// delete, Return/Tab/Space insert, arrows and Home/End move the caret.
    private mutating func applyKey(_ call: RecordingSink.Call) {
        let raw = call.arg.split(separator: "|", maxSplits: 1).first.map(String.init) ?? call.arg
        switch Int64(raw) ?? 0 {
        case 51: backspace(1)
        case 117: forwardDelete(1)
        case 36, 76: insert("\n")
        case 48: insert("\t")
        case 49: insert(" ")
        case 123, 115: caret = max(0, caret - 1)
        case 124, 119: caret = min(chars.count, caret + 1)
        default: break
        }
    }
}

// MARK: - Fake text-input client

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
    /// UTF-16 units selected ending at the caret - a real selection, not a
    /// marked range. A native insert replaces it like a real field does.
    var selectionLength = 0

    var text: String {
        String(String(decoding: utf16, as: UTF16.self))
    }

    init(bundleID: String = "com.test.fake") {
        self.clientBundleID = bundleID
    }

    /// Move the caret the way the user does (click, arrows).
    func moveCaret(to location: Int) {
        caret = location
        selectionLength = 0
        markedRange = nil
    }

    /// Select `count` UTF-16 units ending at the caret.
    func select(_ count: Int) {
        selectionLength = count
    }

    func selectedRange() -> NSRange {
        NSRange(location: caret - selectionLength, length: selectionLength)
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
        selectionLength = 0
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
        selectionLength = 0
    }

    /// The character the app types itself when the composer lets the key
    /// through - a native insert replaces the current selection.
    func nativeInsert(_ s: String) {
        if selectionLength > 0 {
            utf16.removeSubrange((caret - selectionLength)..<caret)
            caret -= selectionLength
            selectionLength = 0
        }
        let units = Array(s.utf16)
        utf16.insert(contentsOf: units, at: caret)
        caret += units.count
    }

    /// A native backspace: delete the selection, or one UTF-16 unit before
    /// the caret.
    func nativeBackspace() {
        if selectionLength > 0 {
            utf16.removeSubrange((caret - selectionLength)..<caret)
            caret -= selectionLength
            selectionLength = 0
            return
        }
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

// MARK: - Stub app detector

/// Scripted `AppContextDetector`: `refreshBundleID()` walks `refreshResults`
/// in order (repeating the last entry once exhausted), simulating e.g.
/// Spotlight finishing opening a few hundred ms after Cmd+Space.
final class StubAppDetector: AppContextDetecting {
    var bundleID: String
    private let refreshResults: [String]
    private(set) var refreshCallCount = 0

    init(bundleID: String, refreshResults: [String]) {
        self.bundleID = bundleID
        self.refreshResults = refreshResults
    }

    convenience init(bundleID: String) {
        self.init(bundleID: bundleID, refreshResults: [bundleID])
    }

    func start() {}

    func stop() {}

    func updateBundleID(_ app: NSRunningApplication) {}

    func refreshBundleID() {
        let result = refreshResults[min(refreshCallCount, refreshResults.count - 1)]
        refreshCallCount += 1
        bundleID = result
    }
}

// MARK: - Stub AX injector

final class StubAXInjector: AXTextInjecting {
    var feedSuccess = true
    private(set) var fedChars: [Character] = []
    private(set) var backspaceCount = 0
    private(set) var commitCount = 0
    private(set) var committedBoundaries: [Character] = []
    private(set) var resetCount = 0

    func feed(char: Character) -> Bool {
        fedChars.append(char)
        return feedSuccess
    }

    func backspace() -> Bool {
        backspaceCount += 1
        return true
    }

    func commit(boundary: Character) -> Bool {
        commitCount += 1
        committedBoundaries.append(boundary)
        return false
    }

    func reset() {
        resetCount += 1
    }
}

// MARK: - EventTap fixture

/// Builds an `EventTap` with deterministic settings (the app's registered
/// defaults are overridden by the user's real UserDefaults, so every
/// environment-dependent flag is pinned here).
@discardableResult
func makeEventTap(vietnamese: Bool = true) -> EventTap {
    let manager = InputMethodManager()
    manager.isVietnamese = vietnamese
    let tap = EventTap(inputMethodManager: manager)
    tap._engine.setInputMethod(.telex)
    tap.autoCapitalizeEnabled = false
    tap.autoDisableOnNonLatinLayout = false
    tap.fnHotkeyEnabled = false
    tap.customHotkeyEnabled = false
    // Sentence-language detection is a user setting (default on). Pin it off
    // so no test depends on the developer's real UserDefaults; the tests that
    // cover it turn it on explicitly.
    tap._engine.contextDetectionEnabled = false
    tap.cachedExcludedApps = []
    tap.cachedCompoundApps = []
    tap.cachedChromiumApps = []
    // Bypass apps are code-defined defaults (system UI + Simulator), not
    // user settings — seed the real set so production behavior is preserved.
    tap.cachedBypassApps = defaultBypassApps
    // Pin the frontmost app: `EventTap.init` builds a real
    // `AppContextDetector` that reads NSWorkspace's frontmost app, which is
    // `com.apple.loginwindow` (a bypass app) while the screen is locked -
    // every key would pass through untouched. Tests that need a specific
    // bundle ID or scripted refreshes replace `tap.appDetector` as before.
    tap.appDetector = StubAppDetector(bundleID: "com.example.testhost")
    // Pin secure input off: `IsSecureEventInputEnabled()` is true while the
    // screen is locked, which would pass every event through untouched.
    tap.isSecureEventInputEnabled = { false }
    return tap
}

// MARK: - CGEvent builders

func keyDownEvent(_ keyCode: Int64, flags: CGEventFlags = [], unicode: String? = nil) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(clamping: keyCode), keyDown: true)!
    if let unicode {
        event.keyboardSetUnicodeString(stringLength: unicode.utf16.count, unicodeString: Array(unicode.utf16))
    }
    event.flags = flags
    return event
}

func keyUpEvent(_ keyCode: Int64, flags: CGEventFlags = [], unicode: String? = nil) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(clamping: keyCode), keyDown: false)!
    if let unicode {
        event.keyboardSetUnicodeString(stringLength: unicode.utf16.count, unicodeString: Array(unicode.utf16))
    }
    event.flags = flags
    return event
}

/// Drives `handle()` exactly like the CGEventTap callback would.
@discardableResult
func send(_ tap: EventTap, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    tap.handle(proxy: CGEventTapProxy(bitPattern: 1)!, type: type, event: event)
}

/// Asserts the event was consumed (callback returned nil) and balances the
/// `passRetained` retain when it was not.
func assertConsumed(_ result: Unmanaged<CGEvent>?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(result, "expected event to be consumed \(message)", file: file, line: line)
    result?.release()
}

func assertPassed(_ result: Unmanaged<CGEvent>?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotNil(result, "expected event to pass through \(message)", file: file, line: line)
    result?.release()
}

// MARK: - Engine typing helper

/// Simulates a user typing `input` on a fresh engine and reconstructs the
/// on-screen text from the (backspaces, suffix) diffs — the same math the
/// EventTap injection performs.
func typeString(_ input: String, modern: Bool = true, method: InputMethod = .telex) -> String {
    let engine = EngineBridge()
    engine.setInputMethod(method)
    engine.setModernOrthography(modern)
    var screen = ""
    for ch in input {
        let (bs, out) = engine.feed(char: ch)
        screen = String(screen.dropLast(bs)) + out
    }
    return screen
}
