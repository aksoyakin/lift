import AppKit
import ApplicationServices

// Odağın kimde olduğu tek başına yetmiyor; odağı kimin tuttuğu da önemli.
// isTransient, odaklı pencerenin balon/açılır panel gibi odağını yitirdiği anda
// kapanan bir pencere olduğunu bildirir.
struct FocusedWindow {
    let element: AXUIElement
    let pid: pid_t
    let isTransient: Bool
}

protocol FocusPerforming: AnyObject {
    func focusedWindow() -> FocusedWindow?
    func focus(_ window: AXUIElement, ownedBy pid: pid_t)
}

final class FocusActions: FocusPerforming {
    func focusedWindow() -> FocusedWindow? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(frontmost.processIdentifier)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success,
              let window = value,
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }

        let element = window as! AXUIElement
        return FocusedWindow(element: element,
                             pid: frontmost.processIdentifier,
                             isTransient: !WindowClassification.isFocusable(subrole: Self.subrole(of: element)))
    }

    // kAXRaiseAction çağrılmaz: kAXMain yazımı pencereyi zaten öne alıyor, ayrı
    // bir raise adımının gözlemlenebilir etkisi yok.
    func focus(_ window: AXUIElement, ownedBy pid: pid_t) {
        _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    private static func subrole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success,
              let subrole = value,
              CFGetTypeID(subrole) == CFStringGetTypeID() else { return nil }
        return (subrole as! CFString) as String
    }
}
