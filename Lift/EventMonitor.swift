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
    private var pressedButtons: Set<Int> = []

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

    // Durdurulurken basılı tuş kaydı da silinir: aksi halde monitör sürükleme
    // sırasında durdurulup yeniden başlatılırsa hiç görülmemiş bir bırakma
    // beklenir ve sürükleme kilidi kalıcı olarak açık kalırdı.
    func stop() {
        lastMoveDispatch = nil
        pressedButtons.removeAll()
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            handleMouseMoved()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buttonPressed(event.buttonNumber)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            buttonReleased(event.buttonNumber)
        case .scrollWheel:
            delegate?.eventMonitorDidScroll(self)
        case .keyDown, .flagsChanged:
            delegate?.eventMonitorDidType(self)
        default:
            break
        }
    }

    // Sürükleme ilk tuş basılınca başlar, son tuş bırakılınca biter. Her basımı
    // başlangıç, her bırakmayı bitiş saymak sol tuşla dosya sürüklerken sağ tuşa
    // basıp bırakmayı sürüklemenin sonu sanmak demekti; kilit düşer ve dosya
    // hâlâ elde dolaşırken odak kayardı. Basımı görülmemiş bir tuşun bırakılması
    // (monitör sürükleme ortasında başladıysa) yok sayılır.
    func buttonPressed(_ button: Int) {
        let wasIdle = pressedButtons.isEmpty
        pressedButtons.insert(button)
        guard wasIdle else { return }
        delegate?.eventMonitorDidBeginDrag(self)
    }

    func buttonReleased(_ button: Int) {
        guard pressedButtons.remove(button) != nil, pressedButtons.isEmpty else { return }
        delegate?.eventMonitorDidEndDrag(self)
    }

    private func handleMouseMoved() {
        let now = clock.now()
        if let last = lastMoveDispatch, now - last < Self.mouseMoveThrottle { return }
        lastMoveDispatch = now
        delegate?.eventMonitor(self, didMoveMouseTo: NSEvent.mouseLocation)
    }
}
