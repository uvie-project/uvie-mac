import Cocoa
import InputMethodKit

/// Process-role switchboard for the UVieIM input method. The same executable
/// runs as the app (UVieMac.app) and as the input method (UVieIM.app); the
/// bundle identifier decides which path `main.swift` takes.
///
/// In the IM process NOTHING of the app may start: no AppDelegate, no
/// EventTap, no menu bar, no Sparkle, no global hotkey, no onboarding. The
/// IMK server and the settings plumbing below are the only residents.
enum InputSourceRuntime {
    /// True when this process runs from the UVieIM.app bundle.
    static var isInputMethodProcess: Bool {
        Bundle.main.bundleIdentifier == InputSourceIdentity.bundleID
    }

    /// The shared composer - created once per IM process, settings loaded at
    /// server start and reloaded on the app's settings-changed broadcast.
    static let composer = InputSourceComposer()

    /// The IMK server instance. Kept in a static so it lives for the whole
    /// process lifetime.
    private static var server: IMKServer?

    /// Entry point for the input-method process. Never returns - it hands
    /// the main runloop to NSApplication.
    static func runServer() -> Never {
        // Read the app's settings domain so every `UserDefaults.standard`
        // read in shared code transparently sees the app's settings.
        UserDefaults.standard.addSuite(named: InputSourceIdentity.appDefaultsSuite)
        registerFactoryDefaults()
        Logger.shared.info("UVieIM: input method process starting")
        composer.reloadSettings()

        // Settings push: the app posts this distributed notification when
        // defaults change. cfprefsd propagates to other processes
        // asynchronously, so reload once immediately and once more shortly
        // after to catch the settled value.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(InputSourceIdentity.settingsChangedNotification),
            object: nil,
            queue: .main
        ) { _ in
            InputSourceRuntime.composer.reloadSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                InputSourceRuntime.composer.reloadSettings()
            }
        }

        server = IMKServer(
            name: InputSourceIdentity.connectionName,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
        NSApplication.shared.run()
        // `NSApplication.run()` only returns when the app terminates, which
        // for an input method means the process is being torn down anyway.
        exit(0)
    }
}
