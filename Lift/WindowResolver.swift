import AppKit
import ApplicationServices
import os

struct ResolvedWindow {
    let element: AXUIElement
    let pid: pid_t
}

protocol WindowResolving: AnyObject {
    func window(at cocoaPoint: CGPoint) -> ResolvedWindow?
}

protocol PointerLocating: AnyObject {
    func location() -> CGPoint
}

final class SystemPointerLocator: PointerLocating {
    func location() -> CGPoint { NSEvent.mouseLocation }
}

final class WindowResolver: WindowResolving {
    private static let maxParentWalkDepth = 12

    private static let focusableSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    private static let deadEndRoles: Set<String> = [
        kAXMenuRole as String,
        kAXMenuItemRole as String,
        kAXMenuBarRole as String,
        kAXMenuBarItemRole as String,
        kAXApplicationRole as String,
        "AXDockItem",
    ]

    private static let messagingTimeout: Float = 0.25

    // Eleme nedenini bildirir; kullanımı README "Teşhis" bölümünde.
    private static let diagnostics = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift",
                                            category: "WindowResolver")

    private let systemWide = AXUIElementCreateSystemWide()
    private let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

    init() {
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
    }

    func window(at cocoaPoint: CGPoint) -> ResolvedWindow? {
        guard let axPoint = Self.axPoint(from: cocoaPoint) else { return nil }

        var hitElement: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide,
                                                      Float(axPoint.x),
                                                      Float(axPoint.y),
                                                      &hitElement)
        guard status == .success, let element = hitElement else { return nil }

        let role = Self.stringAttribute(element, kAXRoleAttribute)
        guard let role, !Self.deadEndRoles.contains(role) else { return nil }

        guard let window = enclosingWindow(of: element, role: role) else {
            Self.diagnostics.debug("pencereye ulaşılamadı: hitRole=\(role, privacy: .public)")
            return nil
        }
        guard isFocusable(window) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        guard pid != ownProcessIdentifier else { return nil }

        return ResolvedWindow(element: window, pid: pid)
    }

    // Cocoa koordinatları sol-alt orijinlidir, erişilebilirlik API'si sol-üst bekler.
    private static func axPoint(from cocoaPoint: CGPoint) -> CGPoint? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        return CGPoint(x: cocoaPoint.x, y: primaryScreen.frame.height - cocoaPoint.y)
    }

    // Dört strateji de gerekli: Catalyst/SwiftUI tabanlı uygulamalar (ör. System
    // Settings) alt öğelerinde kAXWindow yayımlamıyor, yalnızca ilk ikisiyle o
    // pencerelere hedef hiç oluşmuyordu.
    private func enclosingWindow(of element: AXUIElement, role: String) -> AXUIElement? {
        if role == kAXWindowRole as String {
            return element
        }
        if let window = Self.elementAttribute(element, kAXWindowAttribute), Self.isWindow(window) {
            return window
        }
        if let topLevel = Self.elementAttribute(element, kAXTopLevelUIElementAttribute),
           Self.isWindow(topLevel) {
            return topLevel
        }

        var current = element
        for _ in 0 ..< Self.maxParentWalkDepth {
            guard let parent = Self.elementAttribute(current, kAXParentAttribute),
                  let parentRole = Self.stringAttribute(parent, kAXRoleAttribute) else { return nil }
            if parentRole == kAXWindowRole as String { return parent }
            guard !Self.deadEndRoles.contains(parentRole) else { return nil }
            current = parent
        }
        return nil
    }

    private static func isWindow(_ element: AXUIElement) -> Bool {
        stringAttribute(element, kAXRoleAttribute) == kAXWindowRole as String
    }

    // Rolün AXWindow olduğu enclosingWindow içinde garanti edilir; burada yeniden
    // okumak her fare örneğinde fazladan bir AX sorgusu demek olurdu.
    private func isFocusable(_ window: AXUIElement) -> Bool {
        let subrole = Self.stringAttribute(window, kAXSubroleAttribute)
        let minimized = Self.boolAttribute(window, kAXMinimizedAttribute)

        guard minimized != true else {
            Self.diagnostics.debug("elendi: pencere küçültülmüş")
            return false
        }
        guard let subrole, Self.focusableSubroles.contains(subrole) else {
            Self.diagnostics.debug("elendi: uygun olmayan subrole=\(subrole ?? "<yok>", privacy: .public)")
            return false
        }
        return true
    }

    // MARK: - AX öznitelik yardımcıları

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}
