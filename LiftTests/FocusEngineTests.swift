import ApplicationServices
import XCTest
@testable import Lift

final class FocusEngineTests: XCTestCase {
    private var settings: MockSettings!
    private var resolver: MockWindowResolver!
    private var actions: MockFocusActions!
    private var pointer: MockPointerLocator!
    private var clock: TestClock!
    private var debouncer: TestDebouncer!
    private var engine: FocusEngine!
    private var monitor: EventMonitor!

    private let windowA = TestWindows.make(pid: 101)
    private let windowB = TestWindows.make(pid: 202)

    override func setUp() {
        super.setUp()
        settings = MockSettings()
        resolver = MockWindowResolver()
        actions = MockFocusActions()
        pointer = MockPointerLocator()
        clock = TestClock()
        debouncer = TestDebouncer()
        monitor = EventMonitor(clock: clock)
        engine = FocusEngine(settings: settings,
                             resolver: resolver,
                             actions: actions,
                             pointer: pointer,
                             clock: clock,
                             debouncer: debouncer)
    }

    override func tearDown() {
        engine = nil
        monitor = nil
        super.tearDown()
    }

    // MARK: - Yardımcılar

    private func moveMouse(to point: CGPoint = CGPoint(x: 100, y: 100)) {
        pointer.point = point
        engine.eventMonitor(monitor, didMoveMouseTo: point)
    }

    private func target(_ window: AXUIElement, pid: pid_t) -> ResolvedWindow {
        ResolvedWindow(element: window, pid: pid)
    }

    // MARK: - Test altyapısı

    func testDistinctWindowElementsAreNotEqual() {
        XCTAssertFalse(CFEqual(windowA, windowB))
        XCTAssertTrue(CFEqual(windowA, windowA))
    }

    // MARK: - Odaklama ve debounce

    func testFocusesWindowAfterUninterruptedDelay() {
        resolver.result = target(windowA, pid: 101)

        moveMouse()

        XCTAssertEqual(debouncer.scheduledDelay, 0.150)
        XCTAssertTrue(actions.focusCalls.isEmpty, "Süre dolmadan odak değişmemeli")

        XCTAssertTrue(debouncer.fire())

        XCTAssertEqual(actions.focusCalls.count, 1)
        XCTAssertEqual(actions.focusCalls.first?.pid, 101)
        XCTAssertTrue(CFEqual(actions.focusCalls[0].window, windowA))
    }

    func testRepeatedMovesOverSameWindowDoNotRestartTimer() {
        resolver.result = target(windowA, pid: 101)

        moveMouse()
        let cancelsAfterFirstMove = debouncer.cancelCount

        moveMouse(to: CGPoint(x: 110, y: 105))
        moveMouse(to: CGPoint(x: 120, y: 108))

        XCTAssertEqual(debouncer.cancelCount, cancelsAfterFirstMove,
                       "Aynı pencere üzerinde kalırken sayaç sıfırlanmamalı")
        XCTAssertTrue(debouncer.hasPendingAction)
    }

    func testPendingFocusIsCancelledWhenPointerLeavesWindow() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()
        XCTAssertTrue(debouncer.hasPendingAction)

        resolver.result = nil
        moveMouse(to: CGPoint(x: 900, y: 900))

        XCTAssertFalse(debouncer.hasPendingAction)
        XCTAssertFalse(debouncer.fire())
        XCTAssertTrue(actions.focusCalls.isEmpty)
    }

    func testSwitchingWindowBeforeDelayRetargetsInsteadOfFocusingFirst() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()

        resolver.result = target(windowB, pid: 202)
        moveMouse(to: CGPoint(x: 500, y: 400))

        XCTAssertTrue(debouncer.fire())
        XCTAssertEqual(actions.focusCalls.count, 1)
        XCTAssertTrue(CFEqual(actions.focusCalls[0].window, windowB))
    }

    func testDoesNotFocusWhenPointerMovedAwayBeforeTimerFires() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()

        resolver.result = target(windowB, pid: 202)
        XCTAssertTrue(debouncer.fire())

        XCTAssertTrue(actions.focusCalls.isEmpty, "Yeniden doğrulama başarısızsa odaklama yapılmamalı")
    }

    // MARK: - Zaten odaklı pencere

    func testNoWriteWhenTargetIsAlreadyFocusedWindow() {
        actions.focused = windowA
        resolver.result = target(windowA, pid: 101)

        moveMouse()

        XCTAssertFalse(debouncer.hasPendingAction)
        XCTAssertTrue(actions.focusCalls.isEmpty)
    }

    func testAnotherWindowOfTheSameAppIsAValidTarget() {
        actions.focused = windowA
        resolver.result = target(TestWindows.alternate(), pid: 101)

        moveMouse()
        XCTAssertTrue(debouncer.fire())

        XCTAssertEqual(actions.focusCalls.count, 1)
        XCTAssertEqual(actions.focusCalls.first?.pid, 101)
    }

    // MARK: - Sürükleme kilidi

    func testDragCancelsPendingFocusAndBlocksNewOnes() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()
        XCTAssertTrue(debouncer.hasPendingAction)

        engine.eventMonitorDidBeginDrag(monitor)
        XCTAssertFalse(debouncer.hasPendingAction, "Sürükleme bekleyen zamanlayıcıyı iptal etmeli")

        moveMouse(to: CGPoint(x: 400, y: 300))
        XCTAssertFalse(debouncer.hasPendingAction, "Sürükleme sırasında odaklama planlanmamalı")
        XCTAssertTrue(actions.focusCalls.isEmpty)
    }

    func testNormalBehaviourResumesAfterDragEnds() {
        resolver.result = target(windowA, pid: 101)
        engine.eventMonitorDidBeginDrag(monitor)
        moveMouse()
        XCTAssertFalse(debouncer.hasPendingAction)

        engine.eventMonitorDidEndDrag(monitor)

        XCTAssertTrue(debouncer.hasPendingAction, "Tuş bırakılınca normal davranış dönmeli")
        XCTAssertTrue(debouncer.fire())
        XCTAssertEqual(actions.focusCalls.count, 1)
    }

    // MARK: - Kaydırma kilidi

    func testScrollBlocksFocusForThreeHundredMilliseconds() {
        resolver.result = target(windowA, pid: 101)
        clock.time = 10
        engine.eventMonitorDidScroll(monitor)

        clock.time = 10.1
        moveMouse()

        XCTAssertTrue(actions.focusCalls.isEmpty, "Kaydırma kilidi sırasında odak değişmemeli")
        XCTAssertEqual(debouncer.scheduledDelay ?? -1, 0.2, accuracy: 0.0001,
                       "Kilidin kalan süresi kadar yeniden değerlendirme planlanmalı")

        clock.time = 10.3
        XCTAssertTrue(debouncer.fire())
        XCTAssertEqual(debouncer.scheduledDelay, 0.150)
        XCTAssertTrue(actions.focusCalls.isEmpty)

        XCTAssertTrue(debouncer.fire())
        XCTAssertEqual(actions.focusCalls.count, 1)
    }

    // MARK: - Yazma kilidi

    func testTypingGuardBlocksFocusThenReleasesIt() {
        settings.typingGuardMs = 1000
        resolver.result = target(windowA, pid: 101)

        clock.time = 5
        engine.eventMonitorDidType(monitor)

        clock.time = 5.5
        moveMouse()

        XCTAssertTrue(actions.focusCalls.isEmpty, "Yazma kilidi sırasında odak değişmemeli")
        XCTAssertEqual(debouncer.scheduledDelay ?? -1, 0.5, accuracy: 0.0001)

        clock.time = 6.0
        XCTAssertTrue(debouncer.fire())
        XCTAssertEqual(debouncer.scheduledDelay, 0.150)

        XCTAssertTrue(debouncer.fire())
        XCTAssertEqual(actions.focusCalls.count, 1)
    }

    func testTypingDuringDebounceCancelsPendingFocus() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()

        engine.eventMonitorDidType(monitor)

        XCTAssertFalse(debouncer.hasPendingAction)
        XCTAssertTrue(actions.focusCalls.isEmpty)
    }

    // MARK: - Devre dışı durumu

    func testDisabledEngineMakesNoAccessibilityQueries() {
        settings.isEnabled = false
        resolver.result = target(windowA, pid: 101)

        moveMouse()

        XCTAssertEqual(resolver.queryCount, 0, "Kapalıyken AX sorgusu yapılmamalı")
        XCTAssertEqual(actions.focusedWindowQueryCount, 0)
        XCTAssertFalse(debouncer.hasPendingAction)
        XCTAssertTrue(actions.focusCalls.isEmpty)
    }

    func testDisablingCancelsPendingFocus() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()
        XCTAssertTrue(debouncer.hasPendingAction)

        settings.isEnabled = false
        engine.settingsDidChange()

        XCTAssertFalse(debouncer.hasPendingAction)
    }

    // MARK: - Kendi menümüz açıkken

    func testSuspendedEngineDoesNotStealFocusWhileOwnMenuIsOpen() {
        resolver.result = target(windowA, pid: 101)
        moveMouse()
        XCTAssertTrue(debouncer.hasPendingAction)

        engine.setSuspended(true)
        XCTAssertFalse(debouncer.hasPendingAction)

        moveMouse(to: CGPoint(x: 600, y: 500))
        XCTAssertFalse(debouncer.hasPendingAction)
        XCTAssertTrue(actions.focusCalls.isEmpty)

        engine.setSuspended(false)
        XCTAssertTrue(debouncer.hasPendingAction, "Menü kapanınca normal davranış dönmeli")
    }

    // MARK: - Sorgu sırası

    func testGuardsRunBeforeAnyAccessibilityQuery() {
        resolver.result = target(windowA, pid: 101)
        engine.eventMonitorDidBeginDrag(monitor)

        moveMouse()

        XCTAssertEqual(resolver.queryCount, 0, "Kilit aktifken pahalı AX sorgusu yapılmamalı")
    }

    // MARK: - Ayarların anında etkisi

    func testDelaySettingTakesEffectImmediately() {
        settings.delayMs = 500
        resolver.result = target(windowA, pid: 101)

        moveMouse()

        XCTAssertEqual(debouncer.scheduledDelay, 0.5)
    }
}
