import Cocoa
import Carbon

/// Install/enable/select/uninstall the UVieIM input-method bundle. Pure
/// Carbon TIS + FileManager - no Accessibility, no event tap.
enum InputSourceInstaller {

    /// The IM bundle shipped inside the app bundle
    /// (`Contents/Helpers/UVieIM.app`). In dev builds the
    /// `UVIE_IM_BUNDLE` env var points at a bundle produced by
    /// `scripts/build-im-bundle.sh` instead.
    static var bundledURL: URL? {
        let embedded = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/UVieIM.app")
        if FileManager.default.fileExists(atPath: embedded.path) {
            return embedded
        }
        if let env = ProcessInfo.processInfo.environment["UVIE_IM_BUNDLE"],
           FileManager.default.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        return nil
    }

    /// Where macOS loads the input method from.
    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/UVieIM.app")
    }

    enum InstallError: Error {
        case bundleMissing
    }

    /// Copy the bundled IM to `~/Library/Input Methods` and register it.
    /// Any running IM process is terminated first so it cannot hold the old
    /// bundle open.
    static func install() throws {
        guard let bundledURL else { throw InstallError.bundleMissing }
        let fm = FileManager.default
        if fm.fileExists(atPath: installedURL.path) {
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: InputSourceIdentity.bundleID) {
                app.forceTerminate()
            }
            try fm.removeItem(at: installedURL)
        }
        try fm.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.copyItem(at: bundledURL, to: installedURL)
        TISRegisterInputSource(installedURL as CFURL)
    }

    /// The registered UVie input source, when installed.
    static func inputSource() -> TISInputSource? {
        findInputSource(id: InputSourceIdentity.bundleID)
    }

    /// Enable and select the UVie input method, remembering the current
    /// keyboard layout so `deselectAndDisable` can return to it.
    /// Synchronous - callers that need to wait for the registration retry.
    /// Returns true ONLY when the source is actually selected afterwards:
    /// the TIS calls can report noErr while the selection silently fails,
    /// so the observable state is the only trustworthy answer.
    @discardableResult
    static func enableAndSelect() -> Bool {
        guard let source = inputSource() else { return false }
        if !isSelected,
           let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let id = sourceID(of: current) {
            UserDefaults.standard.set(id, forKey: DefaultsKey.inputSourcePreviousLayout)
        }
        guard TISEnableInputSource(source) == noErr,
              TISSelectInputSource(source) == noErr else { return false }
        return isSelected
    }

    /// Select the stored previous layout (fallback ABC, then US) and disable
    /// our input source.
    static func deselectAndDisable() {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.inputSourcePreviousLayout)
        for id in [stored, "com.apple.keylayout.ABC", "com.apple.keylayout.US"].compactMap({ $0 }) {
            if let source = findInputSource(id: id) {
                TISSelectInputSource(source)
                break
            }
        }
        if let source = inputSource() {
            TISDisableInputSource(source)
        }
    }

    /// Deselect, disable, terminate the IM process and remove the bundle.
    static func uninstall() {
        deselectAndDisable()
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: InputSourceIdentity.bundleID) {
            app.forceTerminate()
        }
        try? FileManager.default.removeItem(at: installedURL)
    }

    /// An installed copy whose version differs from the bundled one should
    /// be re-installed (app updated since the IM was installed).
    static func needsUpdate() -> Bool {
        guard let bundledURL else { return false }
        return needsUpdate(bundled: bundledURL, installed: installedURL)
    }

    /// Version comparison over arbitrary bundle URLs - the part unit tests
    /// drive with temp directories.
    static func needsUpdate(bundled: URL, installed: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: installed.path) else { return false }
        return bundleVersion(of: bundled) != bundleVersion(of: installed)
    }

    /// CFBundleVersion of a bundle, read straight from its Info.plist so
    /// tests can use minimal fake bundles.
    static func bundleVersion(of bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any] else { return nil }
        return dict["CFBundleVersion"] as? String
    }

    /// True while the UVie input method is the selected input source.
    static var isSelected: Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = sourceID(of: current) else { return false }
        return id == InputSourceIdentity.bundleID
    }

    // MARK: - TIS helpers

    private static func findInputSource(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue()
                as? [TISInputSource] else { return nil }
        return list.first
    }

    private static func sourceID(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

/// The install/select surface `InputSourceModeController` drives - a seam
/// so the controller's state machine is testable without touching TIS.
protocol InputSourceInstalling {
    /// An IM bundle exists to install (embedded in the app, or via
    /// `UVIE_IM_BUNDLE` in dev).
    var bundledAvailable: Bool { get }
    /// The source is registered and found in the input-source list.
    var isInstalled: Bool { get }
    /// The UVie input method is the currently selected input source.
    var isSelected: Bool { get }
    func needsUpdate() -> Bool
    func install() throws
    /// True ONLY if the source is the selected input source afterwards.
    func enableAndSelect() -> Bool
    func deselectAndDisable()
    func uninstall()
}

/// Production implementation: forwards to the `InputSourceInstaller`
/// statics (Carbon TIS + FileManager).
struct SystemInputSourceInstaller: InputSourceInstalling {
    var bundledAvailable: Bool { InputSourceInstaller.bundledURL != nil }
    var isInstalled: Bool { InputSourceInstaller.inputSource() != nil }
    var isSelected: Bool { InputSourceInstaller.isSelected }
    func needsUpdate() -> Bool { InputSourceInstaller.needsUpdate() }
    func install() throws { try InputSourceInstaller.install() }
    func enableAndSelect() -> Bool { InputSourceInstaller.enableAndSelect() }
    func deselectAndDisable() { InputSourceInstaller.deselectAndDisable() }
    func uninstall() { InputSourceInstaller.uninstall() }
}
