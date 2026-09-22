import AppKit

protocol EventMonitorDelegate: AnyObject {
    func eventMonitor(_ monitor: EventMonitor, didMoveMouseTo point: CGPoint)
    func eventMonitorDidBeginDrag(_ monitor: EventMonitor)
    func eventMonitorDidEndDrag(_ monitor: EventMonitor)
    func eventMonitorDidScroll(_ monitor: EventMonitor)
    func eventMonitorDidType(_ monitor: EventMonitor)
}

final class EventMonitor {
    private static let mouseMoveThrottle: TimeInterval = 0.05

    private static let observedMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseUp, .rightMouseUp, .otherMouseUp,
        .scrollWheel,
        .keyDown, .flagsChanged,
    ]

    weak var delegate: EventMonitorDelegate?

    private let clock: MonotonicClock
    private var monitor: Any?
    private var lastMoveDispatch: TimeInterval?

    init(clock: MonotonicClock = SystemClock()) {
        self.clock = clock
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: Self.observedMask) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        lastMoveDispatch = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            handleMouseMoved()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            delegate?.eventMonitorDidBeginDrag(self)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            delegate?.eventMonitorDidEndDrag(self)
        case .scrollWheel:
            delegate?.eventMonitorDidScroll(self)
        case .keyDown, .flagsChanged:
            delegate?.eventMonitorDidType(self)
        default:
            break
        }
    }

    private func handleMouseMoved() {
        let now = clock.now()
        if let last = lastMoveDispatch, now - last < Self.mouseMoveThrottle { return }
        lastMoveDispatch = now
        delegate?.eventMonitor(self, didMoveMouseTo: NSEvent.mouseLocation)
    }
}
