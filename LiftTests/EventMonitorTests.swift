import AppKit
import XCTest
@testable import Lift

private final class SpyMonitorDelegate: EventMonitorDelegate {
    private(set) var beginDragCount = 0
    private(set) var endDragCount = 0

    func eventMonitor(_ monitor: EventMonitor, didMoveMouseTo point: CGPoint) {}
    func eventMonitorDidBeginDrag(_ monitor: EventMonitor) { beginDragCount += 1 }
    func eventMonitorDidEndDrag(_ monitor: EventMonitor) { endDragCount += 1 }
    func eventMonitorDidScroll(_ monitor: EventMonitor) {}
    func eventMonitorDidType(_ monitor: EventMonitor) {}
}

final class EventMonitorTests: XCTestCase {
    private enum Button {
        static let left = 0
        static let right = 1
        static let middle = 2
    }

    private var delegate: SpyMonitorDelegate!
    private var monitor: EventMonitor!

    override func setUp() {
        super.setUp()
        delegate = SpyMonitorDelegate()
        monitor = EventMonitor(clock: TestClock())
        monitor.delegate = delegate
    }

    override func tearDown() {
        monitor = nil
        delegate = nil
        super.tearDown()
    }

    func testSingleButtonBeginsAndEndsDragOnce() {
        monitor.buttonPressed(Button.left)
        XCTAssertEqual(delegate.beginDragCount, 1)
        XCTAssertEqual(delegate.endDragCount, 0)

        monitor.buttonReleased(Button.left)
        XCTAssertEqual(delegate.beginDragCount, 1)
        XCTAssertEqual(delegate.endDragCount, 1)
    }

    func testSecondButtonDoesNotBeginASecondDrag() {
        monitor.buttonPressed(Button.left)
        monitor.buttonPressed(Button.right)

        XCTAssertEqual(delegate.beginDragCount, 1, "Sürükleme yalnızca ilk tuşta başlamalı")
    }

    // Asıl hata buydu: sol tuşla sürüklerken sağ tuşa basıp bırakmak sürüklemeyi
    // bitmiş sayıyor, kilit düşüyor ve dosya hâlâ elde dolaşırken odak kayıyordu.
    func testReleasingOneOfTwoButtonsDoesNotEndDrag() {
        monitor.buttonPressed(Button.left)
        monitor.buttonPressed(Button.right)

        monitor.buttonReleased(Button.right)
        XCTAssertEqual(delegate.endDragCount, 0, "Hâlâ basılı tuş varken sürükleme bitmemeli")

        monitor.buttonReleased(Button.left)
        XCTAssertEqual(delegate.endDragCount, 1, "Son tuş bırakılınca sürükleme bitmeli")
    }

    func testDragEndsOnlyAfterEveryButtonIsReleased() {
        monitor.buttonPressed(Button.left)
        monitor.buttonPressed(Button.right)
        monitor.buttonPressed(Button.middle)

        monitor.buttonReleased(Button.middle)
        monitor.buttonReleased(Button.left)
        XCTAssertEqual(delegate.endDragCount, 0)

        monitor.buttonReleased(Button.right)
        XCTAssertEqual(delegate.endDragCount, 1)
        XCTAssertEqual(delegate.beginDragCount, 1)
    }

    func testReleaseWithoutMatchingPressIsIgnored() {
        monitor.buttonReleased(Button.left)

        XCTAssertEqual(delegate.endDragCount, 0,
                       "Monitör sürükleme ortasında başladıysa sahipsiz bırakma yok sayılmalı")
        XCTAssertEqual(delegate.beginDragCount, 0)
    }

    func testRepeatedPressOfTheSameButtonBeginsDragOnce() {
        monitor.buttonPressed(Button.left)
        monitor.buttonPressed(Button.left)

        XCTAssertEqual(delegate.beginDragCount, 1)

        monitor.buttonReleased(Button.left)
        XCTAssertEqual(delegate.endDragCount, 1)
    }

    func testStoppingClearsHeldButtonsSoTheGuardCannotStickOpen() {
        monitor.buttonPressed(Button.left)
        monitor.stop()

        monitor.buttonReleased(Button.left)
        XCTAssertEqual(delegate.endDragCount, 0, "Durdurulmuş monitörde bırakma yok sayılmalı")

        monitor.buttonPressed(Button.left)
        XCTAssertEqual(delegate.beginDragCount, 2, "Yeniden basım sürüklemeyi baştan başlatmalı")
        monitor.buttonReleased(Button.left)
        XCTAssertEqual(delegate.endDragCount, 1)
    }
}
