import Cocoa
import ApplicationServices
import Combine

/// Detects the currently focused application using AXUIElement,
/// with fallback to NSWorkspace.frontmostApplication.
///
/// Uses NSWorkspace.didActivateApplicationNotification instead of polling.
/// Spotlight detection was removed — it's handled via `AppDefaults.axApps`
/// which contains "com.apple.Spotlight", so AX mode kicks in automatically
/// when Spotlight is the frontmost app.
protocol AppContextDetecting: AnyObject {
    var bundleID: String { get }
    func start()
    func stop()
    func updateBundleID(_ app: NSRunningApplication)
    func refreshBundleID()
}

final class AppContextDetector: AppContextDetecting {
    private var _bundleID: String = ""
    private var cancellables = Set<AnyCancellable>()
    /// Guards against duplicate Combine subscriptions: `start()` is called
    /// from `EventTap.start()`, from the accessibility retry path and from the
    /// launch poll callback, and each call used to add another sink.
    private var isStarted = false

    var bundleID: String {
        // Read from CGEventTap callback (main runloop) and from
        // NSWorkspace notification handler (main). No queue needed.
        _bundleID
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Initial value
        update()

        // Listen for app activations instead of polling.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                self?.update(for: app)
            }
            .store(in: &cancellables)
    }

    /// Update bundleID directly from an NSRunningApplication. Used by
    /// EventTap to ensure bundleID is current before checking excluded state
    /// (Bug #12: Combine sink order between AppContextDetector and
    /// InputMethodManager is not guaranteed, so appDetector.bundleID could
    /// be stale when resetEngineAfterAppSwitch fires).
    func updateBundleID(_ app: NSRunningApplication) {
        _bundleID = app.bundleIdentifier ?? ""
    }

    func stop() {
        cancellables.removeAll()
        isStarted = false
    }

    /// Update on app switch notification. Uses the NSRunningApplication
    /// from the notification when available (avoids an extra AX call),
    /// falling back to AXUIElement focused-app lookup.
    private func update(for app: NSRunningApplication) {
        // The notification's app is the newly activated app — use its
        // bundleIdentifier directly. This is cheaper than AXUIElement.
        _bundleID = app.bundleIdentifier ?? ""
    }

    /// Initial update — no notification payload, so do the full lookup.
    private func update() {
        _bundleID = getFocusedAppBundleID() ?? getFrontmostAppBundleID() ?? ""
    }

    /// Fresh lookup of the focused app's bundleID.
    func refreshBundleID() {
        if let fresh = getFocusedAppBundleID() ?? getFrontmostAppBundleID() {
            _bundleID = fresh
        }
    }

    /// Primary: AXUIElement focused application.
    private func getFocusedAppBundleID() -> String? {
        // Panels such as Spotlight do not always become the focused
        // APPLICATION: the app that was frontmost keeps that role while the
        // panel's search field holds focus. The focused ELEMENT does belong to
        // the panel's process, so prefer it when it maps to an app we inject
        // through AX (Spotlight). Restricted to `axApps` on purpose: for other
        // apps the focused element can live in a helper process (WebContent,
        // extensions) and would misclassify the app.
        if let elementApp = focusedElementBundleID(), axApps.contains(elementApp) {
            return elementApp
        }

        let systemWide = AXUIElementCreateSystemWide()
        // Bound the AX round-trip: this runs on the event-tap callback and a
        // hung target app would otherwise stall the tap past the system
        // timeout (all typing freezes until the tap is re-enabled).
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard result == .success, let focusedApp else { return nil }

        // `AXUIElement` casts are not runtime-checked (`as?` is treated as
        // always succeeding), so verify the CF type before the forced cast.
        // A broken AX hierarchy returning a non-AXUIElement would trap on the
        // event-tap callback (this runs from `refreshBundleID`). Same guard
        // as `EventTap.computeIsFocusedFieldWebContent`.
        guard CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return nil }
        let app = focusedApp as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)

        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            return runningApp.bundleIdentifier
        }
        return nil
    }

    /// BundleID of the process that owns the focused AX element (the field
    /// the user is typing into), if it can be resolved.
    private func focusedElementBundleID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        var pid: pid_t = 0
        AXUIElementGetPid(focused as! AXUIElement, &pid)
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Fallback: NSWorkspace frontmost application.
    private func getFrontmostAppBundleID() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
