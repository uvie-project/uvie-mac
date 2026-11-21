import Cocoa
import XCTest
@testable import UVieMac

/// The broadcaster pushes app-side settings changes to the separate IM
/// process via a distributed notification while the input-source mode is
/// enabled, coalescing bursts, and stays silent while disabled.
final class SharedSettingsBroadcasterTests: XCTestCase {
    private var broadcaster: SharedSettingsBroadcaster!
    private var manager: InputMethodManager!
    private var savedIsVietnamese = true
    private var savedDefaults: [String: Any?] = [:]
    private let savedDefaultsKeys = [
        DefaultsKey.engineEnabled,
        DefaultsKey.inputSourceModeEnabled,
    ]
    private var distObserver: NSObjectProtocol?
    private let distName = Notification.Name(
        InputSourceIdentity.settingsChangedNotification)

    override func setUp() {
        super.setUp()
        for key in savedDefaultsKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        manager = InputMethodManager()
        savedIsVietnamese = manager.isVietnamese
        broadcaster = SharedSettingsBroadcaster(inputMethodManager: manager)
    }

    override func tearDown() {
        broadcaster.setEnabled(false)
        if let distObserver {
            DistributedNotificationCenter.default().removeObserver(distObserver)
        }
        distObserver = nil
        manager.isVietnamese = savedIsVietnamese
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedDefaults = [:]
        super.tearDown()
    }

    private func expectPosts() -> XCTestExpectation {
        let expectation = XCTestExpectation(
            description: "settingsChanged distributed notification")
        distObserver = DistributedNotificationCenter.default().addObserver(
            forName: distName, object: nil, queue: .main
        ) { _ in
            expectation.fulfill()
        }
        return expectation
    }

    func test_enabled_defaultsChangePostsNotification() {
        broadcaster.setEnabled(true)
        let exp = expectPosts()
        UserDefaults.standard.set(false, forKey: DefaultsKey.engineEnabled)
        wait(for: [exp], timeout: 1)
    }

    func test_enabled_languageTogglePostsNotification() {
        broadcaster.setEnabled(true)
        let exp = expectPosts()
        manager.isVietnamese.toggle()
        wait(for: [exp], timeout: 1)
    }

    func test_enabled_rapidChangesCoalesceToFewPosts() {
        broadcaster.setEnabled(true)
        var posts = 0
        let exp = XCTestExpectation(description: "coalesced posts")
        exp.isInverted = false
        distObserver = DistributedNotificationCenter.default().addObserver(
            forName: distName, object: nil, queue: .main
        ) { _ in
            posts += 1
            if posts >= 5 { exp.fulfill() }
        }
        for i in 0..<20 {
            UserDefaults.standard.set(i % 2 == 0,
                                      forKey: DefaultsKey.engineEnabled)
        }
        // Give the coalescer windows to drain; the burst must stay under 5.
        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertLessThan(posts, 5, "20 changes in a burst must coalesce")
    }

    func test_disabled_noNotificationPosted() {
        // Broadcaster never enabled - the default state of the feature.
        let exp = expectPosts()
        exp.isInverted = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.engineEnabled)
        wait(for: [exp], timeout: 0.3)
    }
}
