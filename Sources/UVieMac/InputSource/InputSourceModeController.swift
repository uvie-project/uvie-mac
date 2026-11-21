import Cocoa

/// App-side controller for the optional input-source mode: installs,
/// selects and tracks the UVieIM input method's state for Settings.
@MainActor
final class InputSourceModeController: ObservableObject {
    enum State: Equatable {
        /// The mode is off (the synthetic-event path is the only one used).
        case off
        /// Install / select is in progress.
        case installing
        /// The UVie input method is enabled and selected.
        case active
        /// Install or select failed.
        case failed(String)
        /// No bundled IM exists (e.g. `swift run` without `UVIE_IM_BUNDLE`).
        case unavailable
    }

    static let shared = InputSourceModeController()

    private let installer: InputSourceInstalling
    private let defaults: UserDefaults
    /// Select-retry policy - injectable so tests run without real sleeps.
    var retryCount = 10
    var retryDelayNanoseconds: UInt64 = 300_000_000

    @Published private(set) var state: State = .off

    init(installer: InputSourceInstalling = SystemInputSourceInstaller(),
         defaults: UserDefaults = .standard) {
        self.installer = installer
        self.defaults = defaults
    }

    /// Toggle the feature from Settings. On: write the flag, install the IM
    /// (fresh or when `needsUpdate`), then retry `enableAndSelect` - TIS
    /// registration is asynchronous and the input source may take a moment
    /// to appear. Off: deselect + disable and write the flag; the installed
    /// bundle stays on disk (`uninstall` is the explicit remove button).
    /// Returns the enable Task so callers/tests can await completion (nil
    /// when disabling - that path is synchronous).
    @discardableResult
    func setEnabled(_ on: Bool) -> Task<Void, Never>? {
        if on {
            defaults.set(true, forKey: DefaultsKey.inputSourceModeEnabled)
            state = .installing
            return Task { await enable() }
        }
        installer.deselectAndDisable()
        defaults.set(false, forKey: DefaultsKey.inputSourceModeEnabled)
        state = .off
        return nil
    }

    private func enable() async {
        guard installer.bundledAvailable else {
            state = .unavailable
            return
        }
        do {
            if !installer.isInstalled || installer.needsUpdate() {
                try installer.install()
            }
            for _ in 0..<retryCount {
                if installer.enableAndSelect() {
                    state = .active
                    return
                }
                if retryDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
            }
            // The bundle is installed - leave the flag on: once the user
            // finishes the selection by hand in System Settings, the event
            // tap hands over automatically.
            state = .failed(
                "Chưa bật được bộ gõ UVie. Hãy thêm \"UVie\" trong System Settings > Keyboard > Input Sources rồi chọn nó."
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The "Gỡ bộ gõ" button: remove the installed bundle and drop the flag.
    func uninstall() {
        installer.uninstall()
        defaults.set(false, forKey: DefaultsKey.inputSourceModeEnabled)
        state = .off
    }

    /// App launch: when the mode is enabled and the app was updated since
    /// the IM was installed, install the new copy. The IM is re-selected
    /// only if it was selected before the update.
    func refreshInstalledBundleIfNeeded() {
        guard defaults.bool(forKey: DefaultsKey.inputSourceModeEnabled) else {
            state = .off
            return
        }
        guard installer.needsUpdate() else {
            state = installer.isSelected ? .active : .off
            return
        }
        let wasSelected = installer.isSelected
        do {
            try installer.install()
            if wasSelected {
                _ = installer.enableAndSelect()
            }
            state = installer.isSelected ? .active : .off
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
