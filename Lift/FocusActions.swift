import AppKit
import ApplicationServices

protocol FocusPerforming: AnyObject {
    func focusedWindow() -> AXUIElement?
    func focus(_ window: AXUIElement, ownedBy pid: pid_t)
}

final class FocusActions: FocusPerforming {
    func focusedWindow() -> AXUIElement? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(frontmost.processIdentifier)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success,
              let window = value,
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    // kAXRaiseAction çağrılmaz: kAXMain yazımı pencereyi zaten öne alıyor, ayrı
    // bir raise adımının gözlemlenebilir etkisi yok.
    func focus(_ window: AXUIElement, ownedBy pid: pid_t) {
        _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
