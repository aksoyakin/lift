import ApplicationServices
import Foundation
@testable import Lift

enum TestWindows {
    static func make(pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }
    static func alternate() -> AXUIElement { AXUIElementCreateSystemWide() }
}

final class MockSettings: FocusSettings {
    var isEnabled = true
    var delayMs = 150
    var typingGuardMs = 1000
}

final class MockWindowResolver: WindowResolving {
    var result: ResolvedWindow?
    private(set) var queryCount = 0

    func window(at cocoaPoint: CGPoint) -> ResolvedWindow? {
        queryCount += 1
        return result
    }
}

final class MockFocusActions: FocusPerforming {
    var focused: AXUIElement?
    private(set) var focusedWindowQueryCount = 0
    private(set) var focusCalls: [(window: AXUIElement, pid: pid_t)] = []

    func focusedWindow() -> AXUIElement? {
        focusedWindowQueryCount += 1
        return focused
    }

    func focus(_ window: AXUIElement, ownedBy pid: pid_t) {
        focusCalls.append((window, pid))
        focused = window
    }
}

final class MockPointerLocator: PointerLocating {
    var point: CGPoint = .zero
    func location() -> CGPoint { point }
}

final class TestClock: MonotonicClock {
    var time: TimeInterval = 0
    func now() -> TimeInterval { time }
}

final class TestDebouncer: DebounceScheduling {
    private(set) var scheduledDelay: TimeInterval?
    private(set) var cancelCount = 0

    private var action: (() -> Void)?

    var hasPendingAction: Bool { action != nil }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        scheduledDelay = delay
        self.action = action
    }

    func cancel() {
        cancelCount += 1
        action = nil
        scheduledDelay = nil
    }

    @discardableResult
    func fire() -> Bool {
        guard let action else { return false }
        self.action = nil
        scheduledDelay = nil
        action()
        return true
    }
}
