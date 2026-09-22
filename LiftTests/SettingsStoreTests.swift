import XCTest
@testable import Lift

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var notificationCenter: NotificationCenter!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        notificationCenter = NotificationCenter()
        store = SettingsStore(defaults: defaults, notificationCenter: notificationCenter)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        notificationCenter = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultValuesMatchSpecification() {
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.delayMs, 150)
        XCTAssertEqual(store.typingGuardMs, 1000)
    }

    func testDerivedDurationsAreInSeconds() {
        store.delayMs = 300
        store.typingGuardMs = 1500

        XCTAssertEqual(store.delay, 0.3, accuracy: 0.0001)
        XCTAssertEqual(store.typingGuard, 1.5, accuracy: 0.0001)
    }

    func testValuesArePersisted() {
        store.isEnabled = false
        store.delayMs = 500
        store.typingGuardMs = 250

        let reopened = SettingsStore(defaults: defaults, notificationCenter: notificationCenter)

        XCTAssertFalse(reopened.isEnabled)
        XCTAssertEqual(reopened.delayMs, 500)
        XCTAssertEqual(reopened.typingGuardMs, 250)
    }

    func testEveryWriteEmitsChangeNotification() {
        var received = 0
        let token = notificationCenter.addObserver(forName: SettingsStore.didChangeNotification,
                                                   object: store,
                                                   queue: nil) { _ in received += 1 }
        defer { notificationCenter.removeObserver(token) }

        store.isEnabled = false
        store.delayMs = 100
        store.typingGuardMs = 800

        XCTAssertEqual(received, 3, "Her ayar yazımı anında etki için bildirim yaymalı")
    }

    func testDelayOptionsCoverTheMenuChoices() {
        XCTAssertEqual(SettingsStore.delayOptions, [0, 100, 150, 300, 500])
    }
}
