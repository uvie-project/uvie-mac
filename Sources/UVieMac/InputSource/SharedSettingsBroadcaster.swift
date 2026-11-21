import Cocoa
import Combine

/// Pushes settings changes to the UVieIM input-method process. Started by
/// `AppDelegate` only while `inputSourceModeEnabled` is true; observes
/// `UserDefaults.didChangeNotification` and the language toggle, coalesces
/// to at most one distributed notification per 50 ms.
final class SharedSettingsBroadcaster {
    private let inputMethodManager: InputMethodManager
    private var defaultsObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var pendingPost: DispatchWorkItem?

    private(set) var isRunning = false

    init(inputMethodManager: InputMethodManager) {
        self.inputMethodManager = inputMethodManager
    }

    /// Start or stop broadcasting to follow the feature flag. Safe to call
    /// repeatedly - no-op when the state already matches.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isRunning else { return }
        isRunning = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePost()
        }
        inputMethodManager.$isVietnamese
            .sink { [weak self] _ in self?.schedulePost() }
            .store(in: &cancellables)
    }

    private func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        cancellables.removeAll()
        pendingPost?.cancel()
        pendingPost = nil
    }

    /// Coalesce bursts of defaults writes (a settings pane can write several
    /// keys at once) to at most one broadcast per 50 ms.
    private func schedulePost() {
        guard pendingPost == nil else { return }
        let item = DispatchWorkItem {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(InputSourceIdentity.settingsChangedNotification),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        pendingPost = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pendingPost = nil
            item.perform()
        }
    }
}
