import Foundation
import AppKit
import CoreGraphics
import Sparkle

/// Singleton wrapper around Sparkle's SPUStandardUpdaterController.
///
/// The controller is created once in AppDelegate and shared here so the
/// About pane can trigger manual update checks (`checkForUpdates()`) and
/// query the updater state without holding a direct reference to the
/// AppDelegate. In dev builds (no .app bundle), the controller is nil and
/// `checkForUpdates()` falls back to opening the GitHub releases page.
///
/// It is also Sparkle's `SPUUpdaterDelegate`: UVie is a menu-bar app that
/// rarely quits, so Sparkle's "install on quit" would leave a downloaded
/// update pending for days. When the user opted into automatic installs we
/// take over the install and run it as soon as they are idle.
@MainActor
final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()

    /// Minimum keyboard/mouse idle time before a downloaded update is
    /// installed and the app relaunched, so it never happens mid-typing.
    nonisolated static let installIdleThreshold: TimeInterval = 60
    /// How often the idle gate is re-checked while an install is pending.
    private static let installPollInterval: TimeInterval = 30

    private(set) var controller: SPUStandardUpdaterController?

    /// Set while an automatic install is waiting for the user to go idle.
    private var pendingInstall: (() -> Void)?
    private var installTimer: Timer?

    private override init() {
        super.init()
    }

    /// Called by AppDelegate after creating the controller.
    func register(_ controller: SPUStandardUpdaterController) {
        self.controller = controller
    }

    /// Trigger Sparkle's standard "Check for Updates…" UI.
    /// Falls back to opening GitHub releases page in browser when Sparkle
    /// is not available (dev builds without a .app bundle).
    func checkForUpdates() {
        if let controller {
            controller.checkForUpdates(nil)
        } else if let url = URL(string: "https://github.com/uvie-project/uvie-mac/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when Sparkle can check for updates (network available, etc.).
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// True when Sparkle is available (running from a .app bundle).
    var isAvailable: Bool {
        controller != nil
    }

    // MARK: - Automatic installs

    /// Whether Sparkle downloads (and then installs) updates on its own.
    /// Backed by Sparkle's own persisted setting; dev builds fall back to
    /// UserDefaults so the toggle still works without a controller.
    var automaticallyInstallsUpdates: Bool {
        get {
            guard let updater = controller?.updater else {
                return UserDefaults.standard.bool(forKey: DefaultsKey.autoInstallUpdates)
            }
            return updater.automaticallyDownloadsUpdates
        }
        set {
            guard let updater = controller?.updater else {
                UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoInstallUpdates)
                return
            }
            updater.automaticallyDownloadsUpdates = newValue
            // Silent downloads only happen when background checks are on.
            if newValue {
                updater.automaticallyChecksForUpdates = true
            } else {
                // Opted out mid-flight: Sparkle then installs on quit instead.
                cancelPendingInstall()
            }
        }
    }

    /// Sparkle calls this once a downloaded update is ready to be installed
    /// on quit. Returning true takes control of the install: we run it at the
    /// next idle moment instead of waiting for a quit that may never come.
    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard automaticallyInstallsUpdates else { return false }
        pendingInstall = immediateInstallHandler
        installTimer?.invalidate()
        installTimer = Timer.scheduledTimer(withTimeInterval: Self.installPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.installIfIdle() }
        }
        // The user may already be away - don't wait a whole poll interval.
        installIfIdle()
        return true
    }

    /// Installs and relaunches once the idle gate opens.
    private func installIfIdle() {
        guard let install = pendingInstall else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        guard Self.shouldInstallWhenIdle(secondsSinceLastEvent: idle,
                                         threshold: Self.installIdleThreshold) else { return }
        cancelPendingInstall()
        install()
    }

    /// Drops a pending idle install; Sparkle then falls back to install on quit.
    private func cancelPendingInstall() {
        installTimer?.invalidate()
        installTimer = nil
        pendingInstall = nil
    }

    /// Pure idle gate: install only after the user has been away long enough.
    nonisolated static func shouldInstallWhenIdle(secondsSinceLastEvent: TimeInterval,
                                                  threshold: TimeInterval = 60) -> Bool {
        secondsSinceLastEvent >= threshold
    }
}
