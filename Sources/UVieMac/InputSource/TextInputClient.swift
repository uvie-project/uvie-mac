import Cocoa
import InputMethodKit

/// Minimal seam over the host app's text field for the input-method path.
/// Implemented by `IMKClientAdapter` in production and by fakes in tests, so
/// `InputSourceComposer` logic is unit-testable without IMK.
protocol TextInputClient: AnyObject {
    /// Bundle identifier of the app the text field belongs to.
    var clientBundleID: String { get }
    /// The current selection/caret. `location` is NSNotFound when unknown.
    func selectedRange() -> NSRange
    /// Insert final text. `NSRange(location: NSNotFound, length: 0)` inserts
    /// at the caret / replaces the marked text.
    func insertText(_ text: String, replacementRange: NSRange)
    /// Show `text` as marked (composing) text with the caret at its end.
    /// An empty string clears the marked text.
    func setMarkedText(_ text: String)
}

/// Adapts an `IMKTextInput` client to `TextInputClient`.
final class IMKClientAdapter: TextInputClient {
    private let client: IMKTextInput

    init(_ client: IMKTextInput) {
        self.client = client
    }

    var clientBundleID: String {
        client.bundleIdentifier() ?? ""
    }

    func selectedRange() -> NSRange {
        client.selectedRange()
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        client.insertText(text, replacementRange: replacementRange)
    }

    func setMarkedText(_ text: String) {
        client.setMarkedText(
            text,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
}
