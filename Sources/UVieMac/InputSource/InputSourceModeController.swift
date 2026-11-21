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

    @Published private(set) var state: State = .off

    /// Toggle the feature from Settings. On: write the flag, install the IM
    /// (fresh or when `needsUpdate`), then retry `enableAndSelect` - TIS
    /// registration is asynchronous and the input source may take a moment
    /// to appear. Off: deselect + disable and write the flag; the installed
    /// bundle stays on disk (`uninstall` is the explicit remove button).
    func setEnabled(_ on: Bool) {
        if on {
            UserDefaults.standard.set(true, forKey: DefaultsKey.inputSourceModeEnabled)
            state = .installing
            Task { await enable() }
        } else {
            InputSourceInstaller.deselectAndDisable()
            UserDefaults.standard.set(false, forKey: DefaultsKey.inputSourceModeEnabled)
            state = .off
        }
    }

    private func enable() async {
        guard InputSourceInstaller.bundledURL != nil else {
            state = .unavailable
            return
        }
        do {
            if InputSourceInstaller.inputSource() == nil || InputSourceInstaller.needsUpdate() {
                try InputSourceInstaller.install()
            }
            for _ in 0..<10 {
                if InputSourceInstaller.enableAndSelect() {
                    state = .active
                    return
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            state = .failed("Không chọn được bộ gõ UVie")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The "Gỡ bộ gõ" button: remove the installed bundle and drop the flag.
    func uninstall() {
        InputSourceInstaller.uninstall()
        UserDefaults.standard.set(false, forKey: DefaultsKey.inputSourceModeEnabled)
        state = .off
    }

    /// App launch: when the mode is enabled and the app was updated since
    /// the IM was installed, install the new copy. The IM is re-selected
    /// only if it was selected before the update.
    func refreshInstalledBundleIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.inputSourceModeEnabled) else {
            state = .off
            return
        }
        guard InputSourceInstaller.needsUpdate() else {
            state = InputSourceInstaller.isSelected ? .active : .off
            return
        }
        let wasSelected = InputSourceInstaller.isSelected
        do {
            try InputSourceInstaller.install()
            if wasSelected {
                _ = InputSourceInstaller.enableAndSelect()
            }
            state = InputSourceInstaller.isSelected ? .active : .off
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
