import Cocoa
import InputMethodKit
import XCTest
@testable import UVieMac

/// KeyInput(event:) extraction, the IMKClientAdapter forwarding, the
/// identity strings that must match InputMethod/Info.plist for macOS to
/// load the input method, and the bundle packaging script.
final class InputSourcePlumbingTests: XCTestCase {
    private var savedDefaults: [String: Any?] = [:]
    private let savedDefaultsKeys = [
        DefaultsKey.engineEnabled,
        DefaultsKey.inputMethod,
        DefaultsKey.inputSourceStyle,
    ]

    override func setUp() {
        super.setUp()
        for key in savedDefaultsKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
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
        // The shared composer keeps process state - reset it so one test's
        // composition cannot leak into the next.
        pinComposerDefaults()
        super.tearDown()
    }

    // MARK: - KeyInput(event:)

    private func keyEvent(keyCode: UInt16, characters: String,
                          flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters,
                         charactersIgnoringModifiers: characters.lowercased(),
                         isARepeat: false, keyCode: keyCode)!
    }

    func test_keyInput_mapsPlainKey() {
        let input = KeyInput(event: keyEvent(keyCode: 0, characters: "a"))
        XCTAssertEqual(input.keyCode, 0)
        XCTAssertEqual(input.characters, "a")
        XCTAssertFalse(input.command)
        XCTAssertFalse(input.control)
        XCTAssertFalse(input.option)
    }

    func test_keyInput_shiftKeyKeepsUppercaseCharacter() {
        let input = KeyInput(event: keyEvent(keyCode: 0, characters: "A",
                                             flags: .shift))
        XCTAssertEqual(input.characters, "A")
        XCTAssertFalse(input.command)
    }

    func test_keyInput_chordModifiersMap() {
        let cmd = KeyInput(event: keyEvent(keyCode: 8, characters: "c", flags: .command))
        XCTAssertTrue(cmd.command)
        XCTAssertFalse(cmd.control)
        let ctrl = KeyInput(event: keyEvent(keyCode: 8, characters: "c", flags: .control))
        XCTAssertTrue(ctrl.control)
        XCTAssertFalse(cmd.option)
        let opt = KeyInput(event: keyEvent(keyCode: 8, characters: "ç", flags: .option))
        XCTAssertTrue(opt.option)
        XCTAssertEqual(opt.characters, "ç")
    }

    // MARK: - IMKClientAdapter

    /// Minimal IMKTextInput fake - every call is recorded, nothing else is
    /// needed for the adapter's forwards.
    private final class FakeIMKClient: NSObject, IMKTextInput {
        var bundleID: String? = "com.example.fakeimk"
        var lastMarkedText: String?
        var lastMarkedSelection = NSRange(location: NSNotFound, length: 0)
        var lastMarkedReplacement = NSRange(location: NSNotFound, length: 0)
        var lastInsertText: String?
        var lastInsertRange = NSRange(location: NSNotFound, length: 0)
        var selection = NSRange(location: 7, length: 2)

        func insertText(_ string: Any!, replacementRange: NSRange) {
            lastInsertText = string as? String
            lastInsertRange = replacementRange
        }

        func setMarkedText(_ string: Any!, selectionRange: NSRange,
                           replacementRange: NSRange) {
            lastMarkedText = string as? String
            lastMarkedSelection = selectionRange
            lastMarkedReplacement = replacementRange
        }

        func unmarkText() {}
        func hasMarkedText() -> Bool { false }
        func selectedRange() -> NSRange { selection }
        func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func attributedSubstring(fromProposedRange range: NSRange,
                                 actualRange: NSRangePointer?) -> NSAttributedString! { nil }
        func length() -> Int { 0 }
        func firstRect(forCharacterRange range: NSRange,
                       actualRange: NSRangePointer?) -> NSRect { .zero }
        func characterIndex(for point: NSPoint) -> Int { 0 }
        func doCommand(by aSelector: Selector!) {}
        func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
        func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
        func characterIndex(for point: NSPoint,
                            tracking mode: IMKLocationToOffsetMappingMode,
                            inMarkedRange inMarked: UnsafeMutablePointer<ObjCBool>?) -> Int { 0 }
        func attributes(forCharacterIndex index: Int,
                        lineHeightRectangle rect: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? { nil }
        func validAttributesForMarkedText() -> [Any]? { nil }
        func selectMode(_ mode: String?) {}
        func supportsUnicode() -> Bool { true }
        func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
        func uniqueClientIdentifierString() -> String? { "test-client" }
        func string(from range: NSRange, actualRange: NSRangePointer?) -> String? { nil }
        func windowLevel() -> CGWindowLevel { 0 }
        func bundleIdentifier() -> String! { bundleID }
    }

    func test_adapter_setMarkedTextPassesCaretAtEndSelection() {
        let fake = FakeIMKClient()
        let adapter = IMKClientAdapter(fake)
        adapter.setMarkedText("việt")
        XCTAssertEqual(fake.lastMarkedText, "việt")
        XCTAssertEqual(fake.lastMarkedSelection, NSRange(location: 4, length: 0),
                       "selection must be a caret at the end, in UTF-16 units")
        XCTAssertEqual(fake.lastMarkedReplacement.location, NSNotFound)
    }

    func test_adapter_insertTextForwardsRangeUntouched() {
        let fake = FakeIMKClient()
        let adapter = IMKClientAdapter(fake)
        adapter.insertText("được", replacementRange: NSRange(location: 2, length: 4))
        XCTAssertEqual(fake.lastInsertText, "được")
        XCTAssertEqual(fake.lastInsertRange, NSRange(location: 2, length: 4))
    }

    func test_adapter_selectionAndBundleID() {
        let fake = FakeIMKClient()
        let adapter = IMKClientAdapter(fake)
        XCTAssertEqual(adapter.selectedRange(), NSRange(location: 7, length: 2))
        XCTAssertEqual(adapter.clientBundleID, "com.example.fakeimk")
        fake.bundleID = nil
        XCTAssertEqual(adapter.clientBundleID, "", "nil bundle ID must fall back to empty")
    }

    // MARK: - UVieInputController callbacks

    /// The IMK entry point: a real NSEvent is distilled and forwarded to
    /// the shared composer, and the adapter writes back to the client.
    func test_controller_handleTranslatesEventThroughComposer() {
        pinComposerDefaults()
        let controller = UVieInputController()
        let fake = FakeIMKClient()
        XCTAssertEqual(controller.recognizedEvents(fake),
                       Int(NSEvent.EventTypeMask.keyDown.rawValue))

        for (code, ch) in zip([9, 8, 4, 4, 17], "vieet") {
            let event = keyEvent(keyCode: UInt16(code), characters: String(ch))
            XCTAssertTrue(controller.handle(event, client: fake))
        }
        XCTAssertEqual(fake.lastMarkedText, "viêt")
    }

    /// commitComposition/deactivateServer call `super`, which requires a
    /// live IMK session (crashes outside one) - a system boundary, untested
    /// here. Their only logic is `composer.abandonWord`, covered by
    /// InputSourceComposerTests.test_abandonWordTwice.

    /// The production per-key adapter lifetime: a settings reload after a
    /// half-typed word cannot finalize through the (per-key, never
    /// retained) client, so the shown word is finalized by the NEXT handle
    /// call - before that key is interpreted under the new settings.
    func test_controller_languageOffMidWord_finalizesOnNextKey() {
        pinComposerDefaults()
        let controller = UVieInputController()
        let fake = FakeIMKClient()
        for (code, ch) in zip([9, 8, 4, 4, 38], "vieej") {
            _ = controller.handle(keyEvent(keyCode: UInt16(code), characters: String(ch)),
                                  client: fake)
        }
        XCTAssertEqual(fake.lastMarkedText, "việ")

        // Language off via a distributed-notification style reload: no
        // client is involved.
        UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
        InputSourceRuntime.composer.reloadSettings()

        let consumed = controller.handle(
            keyEvent(keyCode: 17, characters: "t"), client: fake)
        XCTAssertFalse(consumed, "language off - the key passes through")
        XCTAssertEqual(fake.lastInsertText, "việ",
                       "the interrupted word is finalized exactly as shown")
    }

    /// Same deferred finalize, but on the feedable-key path: switching the
    /// input method mid-word finalizes the shown word before the next key
    /// is fed under the new method.
    func test_controller_methodSwitchMidWord_finalizesOnNextKey() {
        pinComposerDefaults()
        let controller = UVieInputController()
        let fake = FakeIMKClient()
        for (code, ch) in zip([17, 8, 4, 4], "tiee") {
            _ = controller.handle(keyEvent(keyCode: UInt16(code), characters: String(ch)),
                                  client: fake)
        }
        XCTAssertEqual(fake.lastMarkedText, "tiê")

        UserDefaults.standard.set("vni", forKey: DefaultsKey.inputMethod)
        InputSourceRuntime.composer.reloadSettings()

        _ = controller.handle(keyEvent(keyCode: 0, characters: "a"), client: fake)
        _ = controller.handle(keyEvent(keyCode: 18, characters: "1"), client: fake)
        XCTAssertEqual(fake.lastInsertText, "tiê")
        XCTAssertEqual(fake.lastMarkedText, "á")
    }

    /// A non-IMK sender or non-keyDown event is declined.
    func test_controller_handleDeclinesForeignInput() {
        let controller = UVieInputController()
        let fake = FakeIMKClient()
        XCTAssertFalse(controller.handle(keyEvent(keyCode: 0, characters: "a"),
                                         client: NSObject()))
        let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [],
                                  timestamp: 0, windowNumber: 0, context: nil,
                                  characters: "a", charactersIgnoringModifiers: "a",
                                  isARepeat: false, keyCode: 0)!
        XCTAssertFalse(controller.handle(up, client: fake))
    }

    /// Pin the settings the shared composer reads so this test does not
    /// depend on the host's real defaults. Other tests restore their own
    /// keys in tearDown; the shared composer is reset too.
    private func pinComposerDefaults() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.engineEnabled)
        UserDefaults.standard.set("telex", forKey: DefaultsKey.inputMethod)
        UserDefaults.standard.set("marked", forKey: DefaultsKey.inputSourceStyle)
        InputSourceRuntime.composer.reloadSettings()
        InputSourceRuntime.composer.abandonWord(IMKClientAdapter(FakeIMKClient()))
    }

    // MARK: - Identity strings vs InputMethod/Info.plist

    /// The IM bundle loads only if the plist's identifier, TIS ID,
    /// connection name and controller class name match what the code uses.
    func test_identityMatchesImBundlePlist() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/UVieMacTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let plistURL = repoRoot
            .appendingPathComponent("InputMethod")
            .appendingPathComponent("Info.plist")
        let plist = try NSDictionary(contentsOf: plistURL, error: ())

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String,
                       InputSourceIdentity.bundleID)
        XCTAssertEqual(plist["TISInputSourceID"] as? String,
                       InputSourceIdentity.bundleID)
        XCTAssertEqual(plist["InputMethodConnectionName"] as? String,
                       InputSourceIdentity.connectionName)
        let className = try XCTUnwrap(plist["InputMethodServerControllerClass"] as? String)
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(className),
                              "\(className) must resolve to the IMK controller class")
        XCTAssertTrue(cls == UVieInputController.self)
        XCTAssertFalse(InputSourceRuntime.isInputMethodProcess,
                       "the test host is the app, not the IM process")
    }

    // MARK: - build-im-bundle.sh

    /// Assemble a real UVieIM.app around a dummy executable and check the
    /// layout, version substitution and ad-hoc signature.
    func test_buildImBundleScript_producesSignedBundle() throws {
        guard let codesign = try? Process.run(URL(fileURLWithPath: "/usr/bin/which"),
                                              arguments: ["codesign"]) else {
            throw XCTSkip("codesign not available")
        }
        _ = codesign
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repoRoot.appendingPathComponent("scripts/build-im-bundle.sh")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("uvieim-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let build = Process()
        build.executableURL = URL(fileURLWithPath: script.path)
        build.arguments = ["/usr/bin/true", tmp.path]
        try build.run()
        build.waitUntilExit()
        XCTAssertEqual(build.terminationStatus, 0)

        let app = tmp.appendingPathComponent("UVieIM.app")
        let contents = app.appendingPathComponent("Contents")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: contents.appendingPathComponent("MacOS/UVieMac").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: contents.appendingPathComponent("Resources/UVieIM.icns").path))

        func plistString(_ key: String, _ url: URL) throws -> String {
            let dict = try NSDictionary(contentsOf: url, error: ())
            return try XCTUnwrap(dict[key] as? String)
        }
        let rootPlist = repoRoot.appendingPathComponent("Info.plist")
        let imPlist = contents.appendingPathComponent("Info.plist")
        try XCTAssertEqual(plistString("CFBundleShortVersionString", imPlist),
                           plistString("CFBundleShortVersionString", rootPlist))
        try XCTAssertEqual(plistString("CFBundleVersion", imPlist),
                           plistString("CFBundleVersion", rootPlist))
        try XCTAssertEqual(plistString("CFBundleIdentifier", imPlist),
                           InputSourceIdentity.bundleID)

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", app.path]
        try verify.run()
        verify.waitUntilExit()
        XCTAssertEqual(verify.terminationStatus, 0,
                       "ad-hoc signed bundle must pass codesign --verify")
    }
}
