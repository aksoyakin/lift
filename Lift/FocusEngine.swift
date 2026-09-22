import ApplicationServices
import Foundation
import os

protocol MonotonicClock: AnyObject {
    func now() -> TimeInterval
}

final class SystemClock: MonotonicClock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

protocol DebounceScheduling: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

final class MainQueueDebouncer: DebounceScheduling {
    private var workItem: DispatchWorkItem?

    deinit { workItem?.cancel() }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

final class FocusEngine: EventMonitorDelegate {
    private static let scrollGuardDuration: TimeInterval = 0.3

    private let settings: FocusSettings
    private let resolver: WindowResolving
    private let actions: FocusPerforming
    private let pointer: PointerLocating
    private let clock: MonotonicClock
    private let debouncer: DebounceScheduling
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift", category: "FocusEngine")

    private var isDragging = false
    private var isSuspended = false
    private var lastScrollAt: TimeInterval?
    private var lastTypingAt: TimeInterval?
    private var pendingWindow: AXUIElement?

    init(settings: FocusSettings,
         resolver: WindowResolving,
         actions: FocusPerforming,
         pointer: PointerLocating,
         clock: MonotonicClock = SystemClock(),
         debouncer: DebounceScheduling = MainQueueDebouncer()) {
        self.settings = settings
        self.resolver = resolver
        self.actions = actions
        self.pointer = pointer
        self.clock = clock
        self.debouncer = debouncer
    }

    // MARK: - EventMonitorDelegate

    func eventMonitor(_ monitor: EventMonitor, didMoveMouseTo point: CGPoint) {
        evaluate(at: point)
    }

    func eventMonitorDidBeginDrag(_ monitor: EventMonitor) {
        isDragging = true
        cancelPending()
    }

    func eventMonitorDidEndDrag(_ monitor: EventMonitor) {
        isDragging = false
        evaluate(at: pointer.location())
    }

    func eventMonitorDidScroll(_ monitor: EventMonitor) {
        lastScrollAt = clock.now()
        cancelPending()
    }

    func eventMonitorDidType(_ monitor: EventMonitor) {
        lastTypingAt = clock.now()
        cancelPending()
    }

    func settingsDidChange() {
        guard settings.isEnabled else {
            cancelPending()
            return
        }
        evaluate(at: pointer.location())
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        guard !suspended else {
            cancelPending()
            return
        }
        evaluate(at: pointer.location())
    }

    // MARK: - Karar mantığı

    // Sıra önemli: ucuz guard'lar önce, pahalı AX sorgusu en sonda.
    private func evaluate(at point: CGPoint) {
        guard settings.isEnabled else {
            cancelPending()
            return
        }
        guard !isDragging else {
            cancelPending()
            return
        }
        guard !isSuspended else {
            cancelPending()
            return
        }

        let now = clock.now()

        // Kilit bitiminde imleç hareketsizse yeni bir olay gelmez ve odak hiç
        // geçmezdi; polling kurmadan tek seferlik yeniden değerlendirme planlanır.
        if let remaining = remainingGuard(at: now) {
            cancelPending()
            debouncer.schedule(after: remaining) { [weak self] in
                guard let self else { return }
                self.evaluate(at: self.pointer.location())
            }
            return
        }

        guard let target = resolver.window(at: point) else {
            cancelPending()
            return
        }
        guard !isAlreadyFocused(target.element) else {
            cancelPending()
            return
        }

        // Aynı pencere üzerinde kalındığı sürece sayaç sıfırlanmaz; aksi halde
        // imleci tam hareketsiz tutmadıkça odak hiç geçmezdi.
        if let pending = pendingWindow, CFEqual(pending, target.element) { return }

        cancelPending()
        pendingWindow = target.element
        debouncer.schedule(after: settings.delay) { [weak self] in
            self?.commitPendingFocus()
        }
    }

    private func commitPendingFocus() {
        guard let target = pendingWindow else { return }
        pendingWindow = nil

        guard settings.isEnabled, !isDragging, !isSuspended else { return }
        guard remainingGuard(at: clock.now()) == nil else { return }

        // Süre dolduğunda imlecin hâlâ aynı pencerede olduğu yeniden doğrulanır.
        guard let current = resolver.window(at: pointer.location()),
              CFEqual(current.element, target) else { return }
        guard !isAlreadyFocused(current.element) else { return }

        logger.debug("Odak değişiyor (pid: \(current.pid, privacy: .public))")
        actions.focus(current.element, ownedBy: current.pid)
    }

    private func remainingGuard(at now: TimeInterval) -> TimeInterval? {
        var remaining: TimeInterval = 0
        if let lastScrollAt {
            remaining = max(remaining, Self.scrollGuardDuration - (now - lastScrollAt))
        }
        if let lastTypingAt {
            remaining = max(remaining, settings.typingGuard - (now - lastTypingAt))
        }
        return remaining > 0 ? remaining : nil
    }

    private func isAlreadyFocused(_ window: AXUIElement) -> Bool {
        guard let focused = actions.focusedWindow() else { return false }
        return CFEqual(focused, window)
    }

    private func cancelPending() {
        pendingWindow = nil
        debouncer.cancel()
    }
}
