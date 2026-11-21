import Cocoa
import InputMethodKit

/// The IMK server-side controller for the UVie input method. All composing
/// logic lives in the process-shared `InputSourceComposer`; this class only
/// translates IMK callbacks into `KeyInput`/`TextInputClient` calls.
/// No candidate window, no menu.
@objc(UVieInputController)
final class UVieInputController: IMKInputController {

    override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown, let input = sender as? IMKTextInput else {
            return false
        }
        return InputSourceRuntime.composer.handle(
            key: KeyInput(event: event),
            client: IMKClientAdapter(input)
        )
    }

    override func commitComposition(_ sender: Any!) {
        if let input = sender as? IMKTextInput {
            InputSourceRuntime.composer.abandonWord(IMKClientAdapter(input))
        }
        super.commitComposition(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        if let input = sender as? IMKTextInput {
            InputSourceRuntime.composer.abandonWord(IMKClientAdapter(input))
        }
        super.deactivateServer(sender)
    }

    override func activateServer(_ sender: Any!) {
        InputSourceRuntime.composer.reloadSettings()
        super.activateServer(sender)
    }
}
