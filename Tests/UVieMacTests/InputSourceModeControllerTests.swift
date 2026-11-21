import Cocoa
import XCTest
@testable import UVieMac

/// Installer seam used to drive `InputSourceModeController` through its
/// states without touching TIS or ~/Library.
private final class FakeInstaller: InputSourceInstalling {
    var bundledAvailable = true
    var isInstalled = true
    var isSelected = false
    var updateNeeded = false
    var installCalls = 0
    var selectAttempts = 0
    var selectSuccessOnAttempt = 1   // 1-based; 0 = never succeeds
    var deselectCalls = 0
    var uninstallCalls = 0
    var installError: Error?

    func needsUpdate() -> Bool { updateNeeded }
    func install() throws {
        installCalls += 1
        if let installError { throw installError }
        isInstalled = true
    }
    func enableAndSelect() -> Bool {
        selectAttempts += 1
        guard selectSuccessOnAttempt > 0, selectAttempts >= selectSuccessOnAttempt else {
            return false
        }
        isSelected = true
        return true
    }
    func deselectAndDisable() {
        deselectCalls += 1
        isSelected = false
    }
    func uninstall() {
        uninstallCalls += 1
        isInstalled = false
        isSelected = false
    }
}

@MainActor
final class InputSourceModeControllerTests: XCTestCase {
    private var installer: FakeInstaller!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var controller: InputSourceModeController!

    override func setUp() {
        super.setUp()
        installer = FakeInstaller()
        suiteName = "uvie.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        controller = InputSourceModeController(installer: installer, defaults: defaults)
        controller.retryCount = 2
        controller.retryDelayNanoseconds = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        controller = nil
        installer = nil
        super.tearDown()
    }

    private func enable() async {
        await controller.setEnabled(true)?.value
    }

    func test_enable_selectSucceedsFirstTry() async {
        await enable()
        XCTAssertEqual(controller.state, .active)
        XCTAssertTrue(defaults.bool(forKey: DefaultsKey.inputSourceModeEnabled))
        XCTAssertEqual(installer.installCalls, 0, "already installed, no reinstall")
        XCTAssertEqual(installer.selectAttempts, 1)
    }

    func test_enable_installsWhenNotInstalled() async {
        installer.isInstalled = false
        await enable()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(installer.installCalls, 1)
    }

    func test_enable_installsWhenOutdated() async {
        installer.updateNeeded = true
        await enable()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(installer.installCalls, 1)
    }

    func test_enable_upToDate_skipsInstall() async {
        installer.updateNeeded = false
        await enable()
        XCTAssertEqual(installer.installCalls, 0)
        XCTAssertEqual(installer.selectAttempts, 1)
    }

    func test_enable_selectFailsAllRetries_showsGuidance() async {
        installer.selectSuccessOnAttempt = 0
        await enable()
        guard case .failed(let message) = controller.state else {
            XCTFail("expected .failed, got \(controller.state)")
            return
        }
        XCTAssertTrue(message.contains("System Settings"))
        XCTAssertTrue(defaults.bool(forKey: DefaultsKey.inputSourceModeEnabled),
                      "flag stays on so a manual selection still hands over")
        XCTAssertEqual(installer.selectAttempts, controller.retryCount)
    }

    func test_enable_selectSucceedsOnSecondRetry() async {
        installer.selectSuccessOnAttempt = 2
        await enable()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(installer.selectAttempts, 2)
    }

    func test_enable_noBundledIM_unavailable() async {
        installer.bundledAvailable = false
        await enable()
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertEqual(installer.installCalls, 0)
    }

    func test_enable_installThrows_failed() async {
        installer.isInstalled = false
        installer.installError = NSError(domain: "test", code: 1,
                                         userInfo: [NSLocalizedDescriptionKey: "disk full"])
        await enable()
        guard case .failed(let message) = controller.state else {
            XCTFail("expected .failed, got \(controller.state)")
            return
        }
        XCTAssertEqual(message, "disk full")
    }

    func test_disable_deselectsAndTurnsOff() {
        controller.setEnabled(false)
        XCTAssertEqual(installer.deselectCalls, 1)
        XCTAssertFalse(defaults.bool(forKey: DefaultsKey.inputSourceModeEnabled))
        XCTAssertEqual(controller.state, .off)
    }

    func test_uninstall_removesAndTurnsOff() {
        controller.uninstall()
        XCTAssertEqual(installer.uninstallCalls, 1)
        XCTAssertFalse(defaults.bool(forKey: DefaultsKey.inputSourceModeEnabled))
        XCTAssertEqual(controller.state, .off)
    }

    // MARK: - Launch refresh

    func test_launchRefresh_flagOff_doesNothing() {
        defaults.set(false, forKey: DefaultsKey.inputSourceModeEnabled)
        controller.refreshInstalledBundleIfNeeded()
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(installer.installCalls, 0)
        XCTAssertEqual(installer.selectAttempts, 0)
    }

    func test_launchRefresh_upToDateAndSelected_active() {
        defaults.set(true, forKey: DefaultsKey.inputSourceModeEnabled)
        installer.updateNeeded = false
        installer.isSelected = true
        controller.refreshInstalledBundleIfNeeded()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(installer.installCalls, 0)
    }

    func test_launchRefresh_upToDateNotSelected_off() {
        defaults.set(true, forKey: DefaultsKey.inputSourceModeEnabled)
        installer.updateNeeded = false
        installer.isSelected = false
        controller.refreshInstalledBundleIfNeeded()
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(installer.installCalls, 0)
    }

    func test_launchRefresh_needsUpdateAndWasSelected_reinstallsAndReselects() {
        defaults.set(true, forKey: DefaultsKey.inputSourceModeEnabled)
        installer.updateNeeded = true
        installer.isSelected = true
        controller.refreshInstalledBundleIfNeeded()
        XCTAssertEqual(installer.installCalls, 1)
        XCTAssertEqual(installer.selectAttempts, 1)
        XCTAssertEqual(controller.state, .active)
    }

    func test_launchRefresh_needsUpdateNotSelected_installsOnly() {
        defaults.set(true, forKey: DefaultsKey.inputSourceModeEnabled)
        installer.updateNeeded = true
        installer.isSelected = false
        controller.refreshInstalledBundleIfNeeded()
        XCTAssertEqual(installer.installCalls, 1)
        XCTAssertEqual(installer.selectAttempts, 0)
        XCTAssertEqual(controller.state, .off)
    }
}
