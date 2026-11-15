import XCTest
@testable import UVieMac

/// Pure logic of the automatic-install gate: a downloaded update is only
/// installed once the user has been idle long enough.
final class UpdateGateTests: XCTestCase {
    func test_idleGateRequiresThreshold() {
        XCTAssertFalse(UpdateManager.shouldInstallWhenIdle(secondsSinceLastEvent: 0))
        XCTAssertFalse(UpdateManager.shouldInstallWhenIdle(secondsSinceLastEvent: 59.9))
        XCTAssertTrue(UpdateManager.shouldInstallWhenIdle(secondsSinceLastEvent: 60))
        XCTAssertTrue(UpdateManager.shouldInstallWhenIdle(secondsSinceLastEvent: 600))
    }

    func test_idleGateHonoursCustomThreshold() {
        XCTAssertFalse(UpdateManager.shouldInstallWhenIdle(secondsSinceLastEvent: 30, threshold: 45))
        XCTAssertTrue(UpdateManager.shouldInstallWhenIdle(secondsSinceLastEvent: 45, threshold: 45))
    }

    func test_shippedThresholdIsOneMinute() {
        XCTAssertEqual(UpdateManager.installIdleThreshold, 60)
    }

    /// The delegate hook must reach ObjC under Sparkle's selector, otherwise
    /// it compiles but is never called and automatic installs silently stop
    /// working (Sparkle would fall back to install-on-quit).
    func test_updaterDelegateHookIsExposedToObjC() {
        let selector = NSSelectorFromString("updater:willInstallUpdateOnQuit:immediateInstallationBlock:")
        XCTAssertTrue(UpdateManager.instancesRespond(to: selector))
    }
}
